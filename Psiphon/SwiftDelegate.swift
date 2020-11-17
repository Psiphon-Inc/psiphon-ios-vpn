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
    case adPresentationStatus(presenting: Bool)
    case checkForDisallowedTrafficAlertNotification
}

struct AppDelegateState: Equatable {
    var appLifecycle: AppLifecycle = .inited
    var adPresentationState: Bool = false
}

struct AppDelegateReducerState: Equatable {
    var appDelegateState: AppDelegateState
    let subscriptionState: SubscriptionState
}

struct AppDelegateEnvironment {
    let feedbackLogger: FeedbackLogger
    let sharedDB: PsiphonDataSharedDB
    let psiCashEffects: PsiCashEffects
    let paymentQueue: PaymentQueue
    let mainViewStore: (MainViewAction) -> Effect<Never>
    let appReceiptStore: (ReceiptStateAction) -> Effect<Never>
    let paymentTransactionDelegate: PaymentTransactionDelegate
    let mainDispatcher: MainDispatcher
    let getCurrentTime: () -> Date
}

let appDelegateReducer = Reducer<AppDelegateReducerState,
                                 AppDelegateAction,
                                 AppDelegateEnvironment> {
    state, action, environment in
    
    switch action {
    
    case .appLifecycleEvent(let lifecycle):
        
        state.appDelegateState.appLifecycle = lifecycle
        
        switch lifecycle {
        case .didFinishLaunching:
            
            return [
                environment.paymentQueue.addObserver(environment.paymentTransactionDelegate)
                    .mapNever(),
                
                environment.appReceiptStore(.localReceiptRefresh).mapNever()
            ]

        case .didBecomeActive:
            return [ Effect(value: .checkForDisallowedTrafficAlertNotification) ]
        default:
            return []
        }
        
    case .adPresentationStatus(presenting: let presenting):
        state.appDelegateState.adPresentationState = presenting
        return []
        
    case .checkForDisallowedTrafficAlertNotification:

        let lastReadSeq = environment.sharedDB
            .getContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum()
        
        // Last sequence number written by the extension
        let writeSeq = environment.sharedDB.getDisallowedTrafficAlertWriteSequenceNum()
        
        guard writeSeq > lastReadSeq else {
            return []
        }
        
        // TODO: The `date` of this event should really be the same as the last seq number read.
        // In the implementation below two AlertEvents for the same seq number, are not equal.
        let alertEvent = AlertEvent(.disallowedTrafficAlert,
                                    date: environment.getCurrentTime())

        var effects = [Effect<AppDelegateAction>]()

        effects.append(
            // Updates disallowed traffic alert read seq number.
            .fireAndForget {
                environment.sharedDB.setContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum(
                    environment.sharedDB.getDisallowedTrafficAlertWriteSequenceNum())
            }
        )

        // Presents disallowed traffic alert only if the user is not subscribed.
        if case .subscribed(_) = state.subscriptionState.status {
            effects.append(
                environment.feedbackLogger.log(.info, "Disallowed traffic alert not presented.")
                    .mapNever()
            )
        } else {
            effects.append(contentsOf: [
                environment.feedbackLogger.log(.info, "Presenting disallowed traffic alert")
                    .mapNever(),
                environment.mainViewStore(.presentAlert(alertEvent)).mapNever(),
            ])
        }

        return effects
    }
    
}

// MARK: SwiftAppDelegate
@objc final class SwiftDelegate: NSObject {
    
    static let instance = SwiftDelegate()

    private var deepLinkingNavigator = DeepLinkingNavigator()
    private let sharedDB = PsiphonDataSharedDB(forAppGroupIdentifier: PsiphonAppGroupIdentifier)
    private let feedbackLogger = FeedbackLogger(PsiphonRotatingFileFeedbackLogHandler())
    private let supportedProducts =
        SupportedAppStoreProducts.fromPlists(types: [.subscription, .psiCash])
    private let userDefaultsConfig = UserDefaultsConfig()
    private let appUpgrade = AppUpgrade()
    private let dateCompare: DateCompare
    private let appSupportFileStore: ApplicationSupportFileStore
    
    private var (lifetime, token) = Lifetime.make()
    private var objcBridge: ObjCBridgeDelegate!
    private var store: Store<AppState, AppAction>!
    private var psiCashLib: PsiCash
    private var environmentCleanup: (() -> Void)?

    private override init() {
        dateCompare = DateCompare(
            getCurrentTime: { Date () },
            compareDates: { Calendar.current.compare($0, to: $1, toGranularity: $2) })
        
        appSupportFileStore = ApplicationSupportFileStore(fileManager: FileManager.default)
        
        psiCashLib = PsiCash(feedbackLogger: self.feedbackLogger)
    }
    
    // Should be called early in the application lifecycle.
    @objc static func setupDebugFlags() {
        #if DEBUG
        Debugging = DebugFlags(buildConfig: .debug)
        #elseif DEV_RELEASE
        Debugging = DebugFlags(buildConfig: .devRelease)
        #else
        Debugging = DebugFlags.disabled(buildConfig: .release)
        #endif
    }

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
            loadResult = .failure(ErrorEvent(.adSDKError(SystemError(error)), date: Date()))
        } else {
            if case .error = status {
                loadResult = .failure(ErrorEvent(.requestedAdFailedToLoad, date: Date()))
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

        print("Build Configuration: '\(String(describing: Debugging.buildConfig))'")

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
        
        // Logs any filesystem errors stored.
        if let error = appSupportFileStore.filesystemError {
            self.feedbackLogger.immediate(.error, "\(error)")
        }
        
        let mainDispatcher = MainDispatcher()
        let globalDispatcher = GlobalDispatcher(qos: .default, name: "globalDispatcher")
        
        self.store = Store(
            initialValue: AppState(),
            reducer: makeAppReducer(feedbackLogger: self.feedbackLogger),
            dispatcher: mainDispatcher,
            feedbackLogger: self.feedbackLogger,
            environment: { [unowned self] store in
                let (environment, cleanup) = makeEnvironment(
                    store: store,
                    feedbackLogger: self.feedbackLogger,
                    sharedDB: self.sharedDB,
                    psiCashClient: self.psiCashLib,
                    psiCashFileStoreRoot: self.appSupportFileStore.psiCashFileStoreRootPath,
                    supportedAppStoreProducts: self.supportedProducts,
                    userDefaultsConfig: self.userDefaultsConfig,
                    standardUserDeaults: UserDefaults.standard,
                    objcBridgeDelegate: objcBridge,
                    rewardedVideoAdBridgeDelegate: self,
                    dateCompare: self.dateCompare,
                    addToDate: { calendarComponent, value, date -> Date? in
                        Calendar.current.date(byAdding: calendarComponent, value: value, to: date)
                    },
                    mainDispatcher: mainDispatcher,
                    globalDispatcher: globalDispatcher,
                    getTopPresentedViewController: {
                        AppDelegate.getTopPresentedViewController()
                    }
                )
                self.environmentCleanup = cleanup
                return environment
            })
        
        self.store.send(.appDelegateAction(.appLifecycleEvent(.didFinishLaunching)))
        self.store.send(vpnAction: .appLaunched)
        self.store.send(.psiCash(.initialize))

        // Registers accepted deep linking URLs.
        deepLinkingNavigator.register(url: PsiphonDeepLinking.psiCashDeepLink) { [unowned self] in
            self.store.send(.mainViewAction(.presentPsiCashScreen(initialTab: .addPsiCash)))
            return true
        }
        deepLinkingNavigator.register(url: PsiphonDeepLinking.speedBoostDeepLink) { [unowned self] in
            self.store.send(.mainViewAction(.presentPsiCashScreen(initialTab: .speedBoost)))
            return true
        }
        
        // Maps connected events to refresh state messages sent to store.
        self.lifetime += self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus)
            .skipRepeats()
            .filter { $0 == .connected }
            .map(value: AppAction.psiCash(.refreshPsiCashState()))
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
            .flatMap(.latest) { [unowned self] vpnStateTunnelLoadStatePair ->
                SignalProducer<Result<Utilities.Unit, ErrorEvent<ErrorRepr>>, Never> in
                
                guard case .loaded(_) = vpnStateTunnelLoadStatePair.second.value else {
                    return Effect(value: .success(.unit))
                }

                let compareValue = (current: vpnStateTunnelLoadStatePair.first.status.tunneled,
                                    expected: vpnStateTunnelLoadStatePair.first.intent)
                
                switch compareValue {
                case (current: .notConnected, expected: .start(transition: .none)):
                    let error = ErrorEvent(
                        ErrorRepr(repr: "Unexpected value '\(vpnStateTunnelLoadStatePair.second)'"),
                        date: self.dateCompare.getCurrentTime()
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
            .map { [unowned self] appState -> Date? in
                if case .subscribed(_) = appState.subscription.status {
                    return nil
                } else {
                    let activeSpeedBoost = appState.psiCash.activeSpeedBoost(self.dateCompare)
                    return activeSpeedBoost?.transaction.localTimeExpiry
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
        
        // Forwards AppState `psiCash.libData.accountTyp` to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.psiCash.libData.accountType)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] accountType in
                if case .account(loggedIn: true) = accountType {
                    objcBridge!.onPsiCashAccountStatusDidChange(true)
                } else {
                    objcBridge!.onPsiCashAccountStatusDidChange(false)
                }
            }

        // Updates PsiphonDateSharedDB `ContainerAppReceiptLatestSubscriptionExpiryDate`
        // based on the app's receipt's latest subscription state.
        self.lifetime += self.store.$value.signalProducer
            .map(\.subscription.status)
            .skipRepeats()
            .startWithValues { [unowned sharedDB] subscriptionStatus in
                switch subscriptionStatus {
                case .notSubscribed, .unknown:
                    sharedDB.setAppReceiptLatestSubscriptionExpiryDate(nil)
                case let .subscribed(purchase):
                    sharedDB.setAppReceiptLatestSubscriptionExpiryDate(purchase.expires)
                }
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

        // Displays alerts related to PsiCash accounts login events.
        self.lifetime += self.store.$value.signalProducer
            .map(\.psiCash.pendingAccountLoginLogout)
            .skipRepeats()
            .startWithValues { [unowned store] maybeLoginLogoutEvent in
                guard let loginLogoutEvent = maybeLoginLogoutEvent else {
                    return
                }

                let maybeAlert: AlertType?
                
                switch loginLogoutEvent.wrapped {
                case .pending(_):
                    maybeAlert = nil
                    
                case let .completed(.left(completedLoginEvent)):
                    
                    switch completedLoginEvent {
                    case let .success(loginResponse):
                        maybeAlert = .psiCashAccountAlert(
                            .loginSuccessAlert(lastTrackerMerge:loginResponse.lastTrackerMerge))

                    case let .failure(errorEvent):
                        switch errorEvent.error {
                        case .tunnelNotConnected:
                            maybeAlert = .psiCashAccountAlert(.tunnelNotConnectedAlert)

                        case .requestError(.errorStatus(.invalidCredentials)):
                            maybeAlert = .psiCashAccountAlert(.incorrectUsernameOrPasswordAlert)

                        case .requestError(.errorStatus(_)),
                             .requestError(.requestFailed(_)):
                            maybeAlert = .psiCashAccountAlert(.operationFailedTryAgainAlert)
                        }
                    }

                case let .completed(.right(completedLogoutEvent)):
                    switch completedLogoutEvent {
                    case .success(_):
                        maybeAlert = .psiCashAccountAlert(.logoutSuccessAlert)

                    case let .failure(errorEvent):
                        switch errorEvent.error {
                        case .tunnelNotConnected:
                            maybeAlert = .psiCashAccountAlert(.tunnelNotConnectedAlert)

                        case .requestError(_):
                            maybeAlert = .psiCashAccountAlert(.operationFailedTryAgainAlert)
                        }
                    }
                    
                }

                // Sends alert to store if one has been set.
                if let alert = maybeAlert {
                    let alertEvent = loginLogoutEvent.map { _ -> AlertType in
                        alert
                    }
                    store!.send(.mainViewAction(.presentAlert(alertEvent)))
                }
            }

        if Debugging.printAppState {

            self.lifetime += self.store.$value.signalProducer
                .skipRepeats()
                .startWithValues { appState in
                    print("*", "-----")
                    dump(appState[keyPath: \.mainView.alertMessages])
                    print("*", "-----")
                }
        }

    }
    
    @objc func applicationDidBecomeActive(_ application: UIApplication) {
        self.store.send(.appDelegateAction(.appLifecycleEvent(.didBecomeActive)))
        self.store.send(.mainViewAction(.applicationDidBecomeActive))
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
        self.store.send(.psiCash(.refreshPsiCashState()))
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
        
        return deepLinkingNavigator.handle(url: url)
    }

    @objc func presentPsiCashViewController(_ initialTab: PsiCashScreenTab) {
        self.store.send(.mainViewAction(.presentPsiCashScreen(initialTab: initialTab)))
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
            userDefaultsConfig: self.userDefaultsConfig,
            mainBundle: .main,
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
        callback(self.psiCashLib.getRewardActivityData().successToOptional())
    }
    
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError> {
        let promise = Promise<Result<Utilities.Unit, SystemErrorEvent>>.pending()
        let objcPromise = promise.then { result -> Error? in
            return result.failureToOptional()?.error
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

    @objc func isCurrentlySpeedBoosted(completionHandler: @escaping (Bool) -> Void) {
        self.store.$value.signalProducer
            .map(\.psiCash)
            .filter{ psiCashState in
                psiCashState.libLoaded
            }
            .take(first: 1)
            .startWithValues { [unowned self] psiCashState in
                // Calls completionHandler with `true` if has an active Speed Boost.
                completionHandler(psiCashState.activeSpeedBoost(self.dateCompare) != nil)
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
            .map { [unowned self] in
                $0.psiCash.activeSpeedBoost(self.dateCompare)
            }
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
    
    @objc func logOutPsiCashAccount() {
        self.store.send(.psiCash(.accountLogout))
    }
    
    @objc func getLocaleForCurrentAppLanguage() -> NSLocale {
        return self.userDefaultsConfig.localeForAppLanguage as NSLocale
    }

    @objc func userSubmittedFeedback(selectedThumbIndex: Int,
                                     comments: String,
                                     email: String,
                                     uploadDiagnostics: Bool) {
        self.store.send(
            .feedbackAction(
                .userSubmittedFeedback(selectedThumbIndex: selectedThumbIndex,
                                       comments: comments,
                                       email: email,
                                       uploadDiagnostics: uploadDiagnostics)))
    }
}
