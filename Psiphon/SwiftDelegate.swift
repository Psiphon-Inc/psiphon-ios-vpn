/*
 * Copyright (c) 2019, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation
import ReactiveSwift
import Promises
import StoreKit
import NetworkExtension
import Utilities
import PsiApi
import AppStoreIAP
import PsiCashClient

enum AppLifecycle: Equatable {
    case inited
    case didFinishLaunching
    case didBecomeActive
    case willResignActive
    case didEnterBackground
    case willEnterForeground
}

enum AppDelegateAction {
    case appLifecycleEvent(AppLifecycle)
    case appDidLaunch(psiCashData: PsiCashLibData)
    case adPresentationStatus(presenting: Bool)
    case checkForDisallowedTrafficAlertNotification
    case _disallowedNotificationAlertPresentation(success: Bool)
}

struct AppDelegateReducerState: Equatable {
    var psiCashBalance: PsiCashBalance
    var psiCash: PsiCashState
    var appDelegate: AppDelegateState
}

struct AppDelegateState: Equatable {
    var appLifecycle: AppLifecycle = .inited
    
    var adPresentationState: Bool = false
    
    /// Represents whether a disallowed traffic alert has been requested to be presented,
    /// but has not yet been presented.
    var pendingPresentingDisallowedTrafficAlert: Bool = false
}

typealias AppDelegateEnvironment = (
    feedbackLogger: FeedbackLogger,
    psiCashPersistedValues: PsiCashPersistedValues,
    sharedDB: PsiphonDataSharedDB,
    psiCashEffects: PsiCashEffects,
    paymentQueue: PaymentQueue,
    appReceiptStore: (ReceiptStateAction) -> Effect<Never>,
    psiCashStore: (PsiCashAction) -> Effect<Never>,
    paymentTransactionDelegate: PaymentTransactionDelegate
)

func appDelegateReducer(
    state: inout AppDelegateReducerState, action: AppDelegateAction,
    environment: AppDelegateEnvironment
) -> [Effect<AppDelegateAction>] {
    switch action {
    case .appLifecycleEvent(let lifecycle):
        state.appDelegate.appLifecycle = lifecycle
        
        switch lifecycle {
        case .didBecomeActive:
            return [ Effect(value: .checkForDisallowedTrafficAlertNotification) ]
        default:
            return []
        }
        
    case .appDidLaunch(psiCashData: let libData):
        state.psiCash.appDidLaunch(libData)
        state.psiCashBalance = .fromStoredExpectedReward(
            libData: libData,
            persisted: environment.psiCashPersistedValues
        )
        
        let nonSubscriptionAuths = environment.sharedDB.getNonSubscriptionEncodedAuthorizations()
        
        return [
            environment.psiCashEffects.expirePurchases(nonSubscriptionAuths).mapNever(),
            environment.paymentQueue.addObserver(environment.paymentTransactionDelegate).mapNever(),
            environment.appReceiptStore(.localReceiptRefresh).mapNever()
        ]
        
    case .adPresentationStatus(presenting: let presenting):
        state.appDelegate.adPresentationState = presenting
        return []
        
    case .checkForDisallowedTrafficAlertNotification:
        
        // If the app is in the background, view controllers can be presented, but
        // not seen by the user.
        // This guard ensures that the user sees the alert dialog.
        guard case .didBecomeActive = state.appDelegate.appLifecycle else {
            return []
        }
        
        guard !state.appDelegate.pendingPresentingDisallowedTrafficAlert else {
            return []
        }
        
        let lastReadSeq = environment.sharedDB
            .getContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum()
        
        // Last sequence number written by the extension
        let writeSeq = environment.sharedDB.getDisallowedTrafficAlertWriteSequenceNum()
        
        guard writeSeq > lastReadSeq else {
            return []
        }
        
        state.appDelegate.pendingPresentingDisallowedTrafficAlert = true
        
        return [
            environment.feedbackLogger.log(.info, "Presenting disallowed traffic alert")
                .mapNever(),
            
            .deferred { fulfill in
                let found = AppDelegate.getTopPresentedViewController()
                    .traversePresentingStackFor(type: RootContainerController.self)
                
                switch found {
                case .notPresent:
                   fulfill(._disallowedNotificationAlertPresentation(success: false))
                   return
                    
                case .presentTopOfStack(let rootViewController),
                     .presentInStack(let rootViewController):
                
                    // FIXME: Accessing global singleton variable
                    let alertController = makeDisallowedTrafficAlertController(
                        onSpeedBoostClicked: {
                            tryPresentPsiCashViewController(
                                tab: .speedBoost,
                                makePsiCashViewController:
                                    SwiftDelegate.instance.makePsiCashViewController(initialTab:),
                                getTopMostPresentedViewController:
                                    AppDelegate.getTopPresentedViewController
                            )
                        },
                        onSubscriptionClicked: {
                            tryPresentSubscriptionViewController(getTopMostPresentedViewController:
                                    AppDelegate.getTopPresentedViewController)
                        })
                    
                    let success = rootViewController.safePresent(alertController, animated: true)
                    
                    fulfill(._disallowedNotificationAlertPresentation(success: success))
                 
                }
                
            }
        ]
        
    case let ._disallowedNotificationAlertPresentation(success: success):
        
        state.appDelegate.pendingPresentingDisallowedTrafficAlert = false
        
        guard success else {
            return [
                environment.feedbackLogger.log(.error, "Failed to present disallowed traffic alert")
                    .mapNever()
            ]
        }
        
        environment.sharedDB.setContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum(
                environment.sharedDB.getDisallowedTrafficAlertWriteSequenceNum())
        
        return []

    }
    
}

// MARK: SwiftAppDelegate
@objc final class SwiftDelegate: NSObject {
    
    static let instance = SwiftDelegate()
    
    private var navigator = Navigator()
    private let sharedDB = PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER)
    private let feedbackLogger = FeedbackLogger(PsiphonRotatingFileFeedbackLogHandler())
    private let supportedProducts =
        SupportedAppStoreProducts.fromPlists(types: [.subscription, .psiCash])
    private let userDefaultsConfig = UserDefaultsConfig()
    private let appUpgrade = AppUpgrade()
    
    private var (lifetime, token) = Lifetime.make()
    private var objcBridge: ObjCBridgeDelegate!
    private var store: Store<AppState, AppAction>!
    private var psiCashLib: PsiCash!
    private var environmentCleanup: (() -> Void)?
    
}

// MARK: Bridge API

extension SwiftDelegate: RewardedVideoAdBridgeDelegate {
    func adPresentationStatus(_ status: AdPresentation) {
        self.store.send(.psiCash(
            .rewardedVideoPresentation(RewardedVideoPresentation(objcAdPresentation: status)))
        )
    }
    
    func adLoadStatus(_ status: AdLoadStatus, error: NSError?) {
        let loadResult: RewardedVideoLoad
        if let error = error {
            // Note that error event is created here as opposed to the origin
            // of where the error occurred. However this is acceptable as long as
            // this function is called once for each error that happened almost immediately.
            loadResult = .failure(ErrorEvent(.adSDKError(SystemError(error))))
        } else {
            if case .error = status {
                loadResult = .failure(ErrorEvent(.requestedAdFailedToLoad))
            } else {
                loadResult = .success(RewardedVideoLoadStatus(objcAdLoadStatus: status))
            }
        }
        self.store.send(.psiCash(.rewardedVideoLoad(loadResult)))
    }
    
    func installVPNConfig() -> Promise<VPNConfigInstallResult> {
        let promise = Promise<VPNConfigInstallResult>.pending()
        
        self.store.$value.signalProducer
            .map(\.vpnState.value.loadState.value)
            .skipRepeats()
            .scan(IndexedPsiphonTPMLoadState(index: 0, value: .nonLoaded))
            { (previous, tpmLoadState) -> IndexedPsiphonTPMLoadState in
                // Indexes `tpmLoadState` emitted items, starting from 0.
                return IndexedPsiphonTPMLoadState(index: previous.index + 1, value: tpmLoadState)
            }.flatMap(.latest) { [unowned self] indexed
                -> SignalProducer<IndexedPsiphonTPMLoadState, Never> in
                
                // Index 1 represents the value of ProviderManagerLoadState before
                // `.reinstallVPNConfig` action is sent.
                
                switch indexed.index {
                case 0:
                    self.feedbackLogger.fatalError("Unexpected index 0")
                    return .empty
                case 1:
                    switch indexed.value {
                    case .nonLoaded:
                        return Effect.never
                    case .noneStored, .loaded(_), .error(_):
                        return Effect(value: indexed)
                    }
                default:
                    switch indexed.value {
                    case .nonLoaded,.noneStored:
                        return Effect.never
                    case .loaded(_), .error(_):
                        return Effect(value: indexed)
                    }
                }
            }
            .take(first: 2)
            .startWithValues { [promise, unowned self] indexed in
                switch indexed.index {
                case 0:
                    self.feedbackLogger.fatalError("Unexpected index 0")
                    return
                case 1:
                    self.store.send(vpnAction: .reinstallVPNConfig)
                default:
                    switch indexed.value {
                    case .nonLoaded, .noneStored:
                        self.feedbackLogger.fatalError("Unexpected value '\(indexed.value)'")
                        return
                    case .loaded(_):
                        promise.fulfill(.installedSuccessfully)
                    case .error(let errorEvent):
                        if case .failedConfigLoadSave(let error) = errorEvent.error {
                            if error.configurationReadWriteFailedPermissionDenied {
                                promise.fulfill(.permissionDenied)
                            } else {
                                promise.fulfill(.otherError)
                            }
                        }
                    }
                }
            }
        
        return promise
    }
    
}

extension SwiftDelegate: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        self.feedbackLogger.immediate(.info, """
            received user notification: identifier: '\(response.notification.request.identifier)'
            """)
        completionHandler()
    }
    
}

// API exposed to ObjC.
extension SwiftDelegate: SwiftBridgeDelegate {
    
    @objc static var bridge: SwiftBridgeDelegate {
        return SwiftDelegate.instance
    }
    
    @objc func applicationWillFinishLaunching(
        _ application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey : Any]?,
        objcBridge: ObjCBridgeDelegate
    ) -> Bool {
        self.objcBridge = objcBridge
        
        // Updates appForegroundState that is shared with the extension.
        self.sharedDB.setAppForegroundState(true)
        
        self.appUpgrade.checkForUpgrade(userDefaultsConfig: self.userDefaultsConfig,
                                        appInfo: AppInfoObjC(),
                                        feedbackLogger: self.feedbackLogger)
        
        if appUpgrade.firstRunOfVersion == true {
            self.objcBridge.updateAvailableEgressRegionsOnFirstRunOfAppVersion()
        }
        
        UNUserNotificationCenter.current().delegate = self
        
        return true
    }
    
    @objc func applicationDidFinishLaunching(
        _ application: UIApplication
    ) {
        self.feedbackLogger.immediate(.info, "applicationDidFinishLaunching")
        
        navigator.register(url: PsiphonDeepLinking.psiCashDeepLink) { [unowned self] in
            tryPresentPsiCashViewController(
                tab: .addPsiCash,
                makePsiCashViewController: self.makePsiCashViewController(initialTab:),
                getTopMostPresentedViewController: AppDelegate.getTopPresentedViewController
            )
            return true
        }
        
        navigator.register(url: PsiphonDeepLinking.speedBoostDeepLink) { [unowned self] in
            tryPresentPsiCashViewController(
                tab: .speedBoost,
                makePsiCashViewController: self.makePsiCashViewController(initialTab:),
                getTopMostPresentedViewController: AppDelegate.getTopPresentedViewController
            )
            return true
        }
                
        self.psiCashLib = PsiCash.make(flags: Debugging)
        
        self.store = Store(
            initialValue: AppState(),
            reducer: makeAppReducer(feedbackLogger: self.feedbackLogger),
            feedbackLogger: self.feedbackLogger,
            environment: { [unowned self] store in
                let (environment, cleanup) = makeEnvironment(
                    store: store,
                    feedbackLogger: self.feedbackLogger,
                    sharedDB: self.sharedDB,
                    psiCashLib: self.psiCashLib,
                    supportedAppStoreProducts: self.supportedProducts,
                    userDefaultsConfig: self.userDefaultsConfig,
                    objcBridgeDelegate: objcBridge,
                    rewardedVideoAdBridgeDelegate: self,
                    calendar: Calendar.current
                )
                self.environmentCleanup = cleanup
                return environment
        })
        
        self.store.send(.appDelegateAction(.appLifecycleEvent(.didFinishLaunching)))
        self.store.send(vpnAction: .appLaunched)
        self.store.send(.appDelegateAction(.appDidLaunch(psiCashData: self.psiCashLib.dataModel())))
        
        // Maps connected events to refresh state messages sent to store.
        self.lifetime += self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus)
            .skipRepeats()
            .filter { $0 == .connected }
            .map(value: AppAction.psiCash(.refreshPsiCashState))
            .send(store: self.store)
        
        // Maps connected events to rejected authorization ID data update.
        // This is true as long as rejected authorization IDs are updated in tunnel provider
        // during `onActiveAuthorizationIDs:` callback, before the `onConnected` callback.
        self.lifetime += self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus)
            .skipRepeats()
            .filter { $0 == .connected }
            .map(value: AppAction.subscriptionAuthStateAction(
                .localDataUpdate(type: .didUpdateRejectedSubscriptionAuthIDs))
            )
            .send(store: self.store)
        
        // Forwards `PsiCashState` updates to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.psiCashBalanceViewModel)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] viewModel in
                objcBridge!.onPsiCashBalanceUpdate(.init(swiftState: viewModel))
        }
        
        // Forwards `SubscriptionStatus` updates to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.subscription.status)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] in
                objcBridge!.onSubscriptionStatus(BridgedUserSubscription.from(state: $0))
        }
        
        // Forwards subscription auth status to ObjCBridgeDelegate.
        self.lifetime += SignalProducer.combineLatest(
            self.store.$value.signalProducer.map(\.subscriptionAuthState).skipRepeats(),
            self.store.$value.signalProducer.map(\.subscription.status).skipRepeats(),
            self.store.$value.signalProducer
                .map(\.vpnState.value.providerVPNStatus.tunneled).skipRepeats()
            ).map {
                SubscriptionBarView.SubscriptionBarState.make(
                    authState: $0.0, subscriptionStatus: $0.1, tunnelStatus: $0.2
                )
            }
            .skipRepeats()
            .startWithValues { [unowned objcBridge] newValue in
                
                objcBridge!.onSubscriptionBarViewStatusUpdate(
                    ObjcSubscriptionBarViewState(swiftState: newValue)
                )
        }
        
        // Forwards VPN status changes to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] in
                objcBridge!.onVPNStatusDidChange($0)
            }
        
        // Monitors state of VPN status and tunnel intent.
        // If there's a mismatch when tunnel intent changes to start,
        // it alerts the user if the error is not resolves within a few seconds.
        self.lifetime += self.store.$value.signalProducer
            .map { appState -> Pair<VPNStatusWithIntent, ProviderManagerLoadState<PsiphonTPM>> in
                Pair(appState.vpnState.value.vpnStatusWithIntent, appState.vpnState.value.loadState)
            }
            .skipRepeats()
            .flatMap(.latest) { vpnStateTunnelLoadStatePair ->
                SignalProducer<Result<Utilities.Unit, ErrorEvent<ErrorRepr>>, Never> in
                
                guard case .loaded(_) = vpnStateTunnelLoadStatePair.second.value else {
                    return Effect(value: .success(.unit))
                }
            
                let compareValue = (current: vpnStateTunnelLoadStatePair.first.status.tunneled,
                                    expected: vpnStateTunnelLoadStatePair.first.intent)
                
                switch compareValue {
                case (current: .notConnected, expected: .start(transition: .none)):
                    let error = ErrorEvent(
                        ErrorRepr(repr: "Unexpected value '\(vpnStateTunnelLoadStatePair.second)'")
                    )
                    
                    // Waits for the specified amount of time before emitting the vpn status
                    // and tunnel intent mismatch error.
                    return Effect(value: .failure(error)).delay(
                        VPNHardCodedValues.vpnStatusAndTunnelIntentMismatchAlertDelay,
                        on: QueueScheduler.main
                    )
                    
                default:
                    return Effect(value: .success(.unit))
                }
            }
            .skipRepeats()
        .startWithValues { [unowned self] (result: Result<Utilities.Unit, ErrorEvent<ErrorRepr>>) in
                switch result {
                case .success(.unit):
                    break
                    
                case .failure(let errorEvent):
                    self.feedbackLogger.immediate(.error, "\(errorEvent)")
                    
                    self.objcBridge!.onVPNStateSyncError(
                        UserStrings.Tunnel_provider_sync_failed_reinstall_config()
                    )
                }
            }
        
        // Forwards SpeedBoost purchase expiry date (if the user is not subscribed)
        // to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map { appState -> Date? in
                if case .subscribed(_) = appState.subscription.status {
                    return nil
                } else {
                    return appState.psiCash.activeSpeedBoost?.transaction.localTimeExpiry
                }
            }
            .skipRepeats()
            .startWithValues{ [unowned objcBridge] speedBoostExpiry in
                objcBridge!.onSpeedBoostActivePurchase(speedBoostExpiry)
            }
        
        self.lifetime += self.store.$value.signalProducer
            .map(\.vpnState.value.startStopState)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] startStopState in
                let value = VPNStartStopStatus.from(startStopState: startStopState)
                objcBridge!.onVPNStartStopStateDidChange(value)
            }
        
        // Forwards AppState `internetReachability` value to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.internetReachability)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] reachabilityStatus in
                objcBridge!.onReachabilityStatusDidChange(reachabilityStatus.networkStatus)
            }
        
        // Opens landing page whenever Psiphon tunnel is connected, with
        // change in value of `VPNState` tunnel intent.
        // Landing page should not be opened after a reconnection due to an In-App purchase.
        // This condition is implicitly handled, since reconnections do not cause a change
        // the in tunnel intent value.
        self.lifetime += self.store.$value.signalProducer
            .map(\.vpnState.value.tunnelIntent)
            .skipRepeats()
            .combinePrevious(initial: .none)
            .filter { (combined: Combined<TunnelStartStopIntent?>) -> Bool in
                
                switch (previous: combined.previous, current: combined.current) {
                case (previous: .stop, current: .start(transition: .none)):
                    return true
                case (previous: .start(transition: .restart), current: .start(transition: .none)):
                    return true
                default:
                    return false
                }
            }
            .flatMap(.latest) { [unowned store] _ in
                // Observes tunnel connected events after the user has switched
                // tunnel intent to `.start(transition: _)`.
                store!.$value.signalProducer
                    .map(\.vpnState.value.providerVPNStatus)
                    .skipRepeats()
                    .filter { $0 == .connected }
                    .take(first: 1)
                    .map(value: AppAction.landingPage(.tunnelConnectedAfterIntentSwitchedToStart))
            }
            .send(store: self.store)

        if Debugging.printAppState {
            self.lifetime += self.store.$value.signalProducer.startWithValues { appState in
                print("*", "-----")
                dump(appState[keyPath: \.subscriptionAuthState])
                print("*", "-----")
            }
        }

    }
    
    @objc func applicationDidBecomeActive(_ application: UIApplication) {
        self.store.send(.appDelegateAction(.appLifecycleEvent(.didBecomeActive)))
    }
    
    @objc func applicationWillResignActive(_ application: UIApplication) {
        self.store.send(.appDelegateAction(.appLifecycleEvent(.willResignActive)))
    }
    
    @objc func applicationWillEnterForeground(_ application: UIApplication) {
        // Updates appForegroundState shared with the extension before
        // syncing with it through the `.syncWithProvider` message.
        self.sharedDB.setAppForegroundState(true)
        
        self.store.send(.appDelegateAction(.appLifecycleEvent(.willEnterForeground)))
        self.store.send(vpnAction: .syncWithProvider(reason: .appEnteredForeground))
        self.store.send(.psiCash(.refreshPsiCashState))
    }
    
    @objc func applicationDidEnterBackground(_ application: UIApplication) {
        self.store.send(.appDelegateAction(.appLifecycleEvent(.didEnterBackground)))
        self.sharedDB.setAppForegroundState(false)
    }
    
    @objc func applicationWillTerminate(_ application: UIApplication) {
        self.environmentCleanup?()
    }

    @objc func application(_ app: UIApplication,
                           open url: URL,
                           options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        
        return navigator.handle(url: url)
    }
    
    @objc func makeSubscriptionBarView() -> SubscriptionBarView {
        SubscriptionBarView { [unowned objcBridge, store] state in
            switch state.authState {
            case .notSubscribed, .subscribedWithAuth:
                objcBridge?.presentSubscriptionIAPViewController()
            
            case .failedRetry:
                store?.send(.appReceipt(.localReceiptRefresh))
        
            case .pending:
                if state.tunnelStatus == .notConnected {
                    objcBridge?.startStopVPNWithInterstitial()
                }
            }
        }
    }
    
    @objc func makePsiCashViewController(
        _ initialTab: PsiCashViewController.PsiCashViewControllerTabs
    ) -> UIViewController {
        self.makePsiCashViewController(initialTab: initialTab)
    }
    
    @objc func makeOnboardingViewControllerWithStagesNotCompleted(
        _ completionHandler: @escaping (OnboardingViewController) -> Void
    ) -> OnboardingViewController? {
        
        // Finds stages that are not completed by the user.
        let stagesNotCompleted = OnboardingStage.findStagesNotCompleted(
            completedStages: self.userDefaultsConfig.onboardingStagesCompletedTyped
        )
        
        guard !stagesNotCompleted.isEmpty else {
            return nil
        }
        
        return OnboardingViewController(
            onboardingStages: stagesNotCompleted,
            feedbackLogger: self.feedbackLogger,
            installVPNConfig: self.installVPNConfig,
            onOnboardingFinished: { [unowned self] onboardingViewController in
                // Updates `userDefaultsConfig` with the latest
                // onboarding stages that are completed.
                self.userDefaultsConfig.onboardingStagesCompleted =
                    OnboardingStage.stagesToComplete.map(\.rawValue)
                
                completionHandler(onboardingViewController)
            }
        )
    }
    
    @objc func completedAllOnboardingStages() -> Bool {
        // Finds stages that are not completed by the user.
        let stagesNotCompleted = OnboardingStage.findStagesNotCompleted(
            completedStages: self.userDefaultsConfig.onboardingStagesCompletedTyped)
        
        return stagesNotCompleted.isEmpty
    }
    
    @objc func isNewInstallation() -> Bool {
        guard let newInstallation = self.appUpgrade.newInstallation else {
            fatalError()
        }
        return newInstallation
    }
    
    @objc func getCustomRewardData(_ callback: @escaping (CustomData?) -> Void) {
        callback(
            PsiCashEffects.default(psiCash: self.psiCashLib, feedbackLogger: self.feedbackLogger)
                .rewardedVideoCustomData()
        )
    }
    
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError> {
        let promise = Promise<Result<Utilities.Unit, SystemErrorEvent>>.pending()
        let objcPromise = promise.then { result -> Error? in
            return result.projectError()?.error
        }
        self.store.send(.appReceipt(.remoteReceiptRefresh(optionalPromise: promise)))
        return objcPromise.asObjCPromise()
    }
    
    @objc func buyAppStoreSubscriptionProduct(
        _ skProduct: SKProduct
    ) -> Promise<ObjCIAPResult>.ObjCPromise<ObjCIAPResult> {
        let promise = Promise<ObjCIAPResult>.pending()
        
        do {
            let appStoreProduct = try AppStoreProduct.from(
                skProduct: skProduct,
                isSupportedProduct: self.supportedProducts.isSupportedProduct(_:)
            )
            
            guard case .subscription = appStoreProduct.type else {
                fatalError()
            }
            
            self.store.send(.iap(.purchase(product: appStoreProduct, resultPromise: promise)))
            
        } catch {
            self.feedbackLogger.fatalError(
                "Unknown subscription product identifier '\(skProduct.productIdentifier)'")
        }
        
        return promise.asObjCPromise()
    }
    
    @objc func onAdPresentationStatusChange(_ presenting: Bool) {
        self.store.send(.appDelegateAction(.adPresentationStatus(presenting: presenting)))
    }
    
    @objc func getAppStoreSubscriptionProductIDs() -> Set<String> {
        return self.supportedProducts.supported[.subscription]!.rawValues
    }
    
    @objc func getAppStateFeedbackEntry(completionHandler: @escaping (String) -> Void) {
        self.store.$value.signalProducer
            .take(first: 1)
            .startWithValues { [unowned self] appState in
                completionHandler("""
                    ContainerInfo: {
                    \"AppState\":\"\(makeFeedbackEntry(appState))\",
                    \"UserDefaultsConfig\":\"\(makeFeedbackEntry(UserDefaultsConfig()))\",
                    \"PsiphonDataSharedDB\": \"\(makeFeedbackEntry(self.sharedDB))\",
                    \"OutstandingEffectCount\": \(self.store.outstandingEffectCount)
                    }
                    """)
        }
    }
    
    @objc func isCurrentlySpeedBoosted(completionHandler: @escaping (Bool) -> Void) {
        self.store.$value.signalProducer
            .map(\.psiCash)
            .filter{ psiCashState in
                psiCashState.libLoaded
            }
            .take(first: 1)
            .startWithValues { psiCashState in
                // Calls completionHandler with `true` if has an active Speed Boost.
                completionHandler(psiCashState.activeSpeedBoost != nil)
        }
        
    }
    
    @objc func disallowedTrafficAlertNotification() {
        self.store.send(.appDelegateAction(.checkForDisallowedTrafficAlertNotification))
    }
    
    @objc func switchVPNStartStopIntent()
        -> Promise<SwitchedVPNStartStopIntent>.ObjCPromise<SwitchedVPNStartStopIntent>
    {
        let promise = Promise<SwitchedVPNStartStopIntent>.pending()
        
        let subscription: SignalProducer<SubscriptionStatus, Never> =
            self.store.$value.signalProducer
                .map(\.subscription.status)
                .filter { $0 != .unknown }
                .take(first: 1)
        
        let syncedVPNState: SignalProducer<VPNProviderManagerState<PsiphonTPM>, Never> =
            self.store.$value.signalProducer
                .map(\.vpnState.value)
                .filter { vpnProviderManagerState -> Bool in
                    if case .completed(_) = vpnProviderManagerState.providerSyncResult {
                        return true
                    } else {
                        return false
                    }
                }
                .take(first: 1)
        
        let activeSpeedBoost: SignalProducer<PurchasedExpirableProduct<SpeedBoostProduct>?, Never> =
            self.store.$value.signalProducer
                .map(\.psiCash.activeSpeedBoost)
                .take(first: 1)
        
        syncedVPNState.zip(with: subscription).zip(with: activeSpeedBoost)
            .map {
                SwitchedVPNStartStopIntent.make(
                    fromProviderManagerState: $0.0.0,
                    subscriptionStatus: $0.0.1,
                    currentActiveSpeedBoost: $0.1
                )
            }.startWithValues { newIntentValue in
                promise.fulfill(newIntentValue)
            }
        
        return promise.asObjCPromise()
    }
    
    @objc func sendNewVPNIntent(_ value: SwitchedVPNStartStopIntent) {
        switch value.switchedIntent {
        case .start(transition: .none):
            self.store.send(vpnAction: .tunnelStateIntent(
                intent: .start(transition: .none), reason: .userInitiated
            ))
        case .stop:
            self.store.send(vpnAction: .tunnelStateIntent(
                intent: .stop, reason: .userInitiated
            ))
        default:
            self.feedbackLogger.fatalError("Unexpected state '\(value.switchedIntent)'")
            return
        }
    }
    
    @objc func restartVPNIfActive() {
        self.store.send(vpnAction: .tunnelStateIntent(
            intent: .start(transition: .restart), reason: .userInitiated
            ))
    }
    
    @objc func syncWithTunnelProvider(reason: TunnelProviderSyncReason) {
        self.store.send(vpnAction: .syncWithProvider(reason: reason))
    }
    
    @objc func reinstallVPNConfig() {
        self.store.send(vpnAction: .reinstallVPNConfig)
    }

    typealias IndexedPsiphonTPMLoadState = Indexed<ProviderManagerLoadState<PsiphonTPM>.LoadState>
    
    @objc func installVPNConfigWithPromise() ->
        Promise<VPNConfigInstallResultWrapper>.ObjCPromise<VPNConfigInstallResultWrapper>
    {
        // Maps Swift type `Promise<VPNConfigInstallResult>` to equivalent ObjC type.
        self.installVPNConfig().then { VPNConfigInstallResultWrapper($0) }.asObjCPromise()
    }
    
    @objc func getLocaleForCurrentAppLanguage() -> NSLocale {
        return self.userDefaultsConfig.localeForAppLanguage as NSLocale
    }
}

fileprivate extension SwiftDelegate {
    
    func makePsiCashViewController(
        initialTab: PsiCashViewController.PsiCashViewControllerTabs
    ) -> PsiCashViewController {
        PsiCashViewController(
            initialTab: initialTab,
            store: self.store.projection(
                value: { $0.psiCashViewController },
                action: { .psiCash($0) }),
            iapStore: self.store.projection(
                value: erase,
                action: { .iap($0) }),
            productRequestStore: self.store.projection(
                value: erase,
                action: { .productRequest($0) } ),
            appStoreReceiptStore: self.store.projection(
                value: erase,
                action: { .appReceipt($0) } ),
            tunnelConnectedSignal: self.store.$value.signalProducer
                .map(\.vpnState.value.providerVPNStatus.tunneled),
            feedbackLogger: self.feedbackLogger
        )
    }
        
}

fileprivate func tryPresentPsiCashViewController(
    tab: PsiCashViewController.PsiCashViewControllerTabs,
    makePsiCashViewController:
        @escaping (PsiCashViewController.PsiCashViewControllerTabs) -> PsiCashViewController,
    getTopMostPresentedViewController: @escaping () -> UIViewController
) {
    let topMostViewController = getTopMostPresentedViewController()
    
    let found = topMostViewController
        .traversePresentingStackFor(type: PsiCashViewController.self)
    
    switch found {
    case .presentInStack(_):
        // NO-OP
        break
        
    case .presentTopOfStack(let psiCashViewController):
        psiCashViewController.activeTab = tab
        
    case .notPresent:
        let psiCashViewController = makePsiCashViewController(tab)
        topMostViewController.present(psiCashViewController, animated: true)
    }
}

fileprivate func tryPresentSubscriptionViewController(
    getTopMostPresentedViewController: @escaping () -> UIViewController
) {
    let topMostViewController = getTopMostPresentedViewController()
    
    let found = topMostViewController
        .traversePresentingStackFor(type: IAPViewController.self)
    
    switch found {
    case .presentTopOfStack(_), .presentInStack(_):
        // NO-OP
        break
    case .notPresent:
        let navCtrl = UINavigationController(rootViewController: IAPViewController())
        topMostViewController.present(navCtrl, animated: true)
        
    }
}
    
fileprivate func makeDisallowedTrafficAlertController(
    onSpeedBoostClicked: @escaping () -> Void,
    onSubscriptionClicked: @escaping () -> Void
) -> UIAlertController {
    
    let alertController = UIAlertController(
        title: UserStrings.Upgrade_psiphon(),
        message: UserStrings.Disallowed_traffic_alert_message(),
        preferredStyle: .alert
    )
    
    alertController.addAction(
        UIAlertAction(
            title: UserStrings.Subscribe_action_button_title(),
            style: .default,
            handler: { _ in
                onSubscriptionClicked()
            })
    )
    
    alertController.addAction(
        UIAlertAction(
            title: UserStrings.Speed_boost(),
            style: .default,
            handler: { _ in
                onSpeedBoostClicked()
            })
    )
    
    return alertController
}
