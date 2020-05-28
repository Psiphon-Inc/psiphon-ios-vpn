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

enum AppDelegateAction {
    case appDidLaunch(psiCashData: PsiCashLibData)
    case adPresentationStatus(presenting: Bool)
}

struct AppDelegateReducerState: Equatable {
    var psiCashBalance: PsiCashBalance
    var psiCash: PsiCashState
    var adPresentationState: Bool
}

typealias AppDelegateEnvironment = (
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
        state.adPresentationState = presenting
        return []
    }
    
}

// MARK: SwiftAppDelegate
@objc final class SwiftDelegate: NSObject {
    
    static let instance = SwiftDelegate()
    
    private let sharedDB = PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER)
    private let feedbackLogger = FeedbackLogger(PsiphonRotatingFileFeedbackLogHandler())
    
    private var (lifetime, token) = Lifetime.make()
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
    
    func adLoadStatus(_ status: AdLoadStatus, error: SystemError?) {
        let loadResult: RewardedVideoLoad
        if let error = error {
            // Note that error event is created here as opposed to the origin
            // of where the error occurred. However this is acceptable as long as
            // this function is called once for each error that happened almost immediately.
            loadResult = .failure(ErrorEvent(.adSDKError(error)))
        } else {
            if case .error = status {
                loadResult = .failure(ErrorEvent(.requestedAdFailedToLoad))
            } else {
                loadResult = .success(RewardedVideoLoadStatus(objcAdLoadStatus: status))
            }
        }
        self.store.send(.psiCash(.rewardedVideoLoad(loadResult)))
    }
}

// API exposed to ObjC.
extension SwiftDelegate: SwiftBridgeDelegate {
    
    @objc static var bridge: SwiftBridgeDelegate {
        return SwiftDelegate.instance
    }
    
    @objc func applicationDidFinishLaunching(
        _ application: UIApplication, objcBridge: ObjCBridgeDelegate
    ) {
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
                    objcBridgeDelegate: objcBridge,
                    rewardedVideoAdBridgeDelegate: self,
                    calendar: Calendar.current
                )
                self.environmentCleanup = cleanup
                return environment
        })
        
        self.store.send(vpnAction: .appLaunched)
        self.store.send(
            .appDelegateAction(.appDidLaunch(psiCashData: self.psiCashLib.dataModel()))
        )
        
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
            .map(\.balanceState)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] balanceViewModel in
                objcBridge.onPsiCashBalanceUpdate(.init(swiftState: balanceViewModel))
        }
        
        // Forwards `SubscriptionStatus` updates to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.subscription.status)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] in
                objcBridge.onSubscriptionStatus(BridgedUserSubscription.from(state: $0))
        }
        
        // Forwards VPN status changes to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] in
                objcBridge.onVPNStatusDidChange($0)
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
                    
                    objcBridge.onVPNStateSyncError(
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
                objcBridge.onSpeedBoostActivePurchase(speedBoostExpiry)
            }
        
        self.lifetime += self.store.$value.signalProducer
            .map(\.vpnState.value.startStopState)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] startStopState in
                let value = VPNStartStopStatus.from(startStopState: startStopState)
                objcBridge.onVPNStartStopStateDidChange(value)
            }
        
        // Forwards AppState `internetReachability` value to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.internetReachability)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] reachabilityStatus in
                objcBridge.onReachabilityStatusDidChange(reachabilityStatus.networkStatus)
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
    
    @objc func applicationWillEnterForeground(_ application: UIApplication) {
        self.store.send(vpnAction: .syncWithProvider(reason: .appEnteredForeground))
        self.store.send(.psiCash(.refreshPsiCashState))
        
        self.sharedDB.setAppForegroundState(true)
    }
    
    @objc func applicationDidEnterBackground(_ application: UIApplication) {
        self.sharedDB.setAppForegroundState(false)
    }
    
    @objc func applicationWillTerminate(_ application: UIApplication) {
        self.environmentCleanup?()
    }
    
    @objc func applicationDidBecomeActive(_ application: UIApplication) {}
    
    @objc func createPsiCashViewController(
        _ initialTab: PsiCashViewController.Tabs
    ) -> UIViewController? {
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
            tunnelConnectedSignal: self.store.$value.signalProducer
                .map(\.vpnState.value.providerVPNStatus.tunneled),
            feedbackLogger: self.feedbackLogger
        )
    }
    
    @objc func getCustomRewardData(_ callback: @escaping (CustomData?) -> Void) {
        callback(
            PsiCashEffects.default(psiCash: self.psiCashLib, feedbackLogger: self.feedbackLogger)
                .rewardedVideoCustomData()
        )
    }
    
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError> {
        let promise = Promise<Result<(), SystemErrorEvent>>.pending()
        let objcPromise = promise.then { result -> Error? in
            return result.projectError()?.error
        }
        self.store.send(.appReceipt(.remoteReceiptRefresh(optionalPromise: promise)))
        return objcPromise.asObjCPromise()
    }
    
    @objc func buyAppStoreSubscriptionProduct(
        _ skProduct: SKProduct
    ) -> Promise<ObjCIAPResult>.ObjCPromise<ObjCIAPResult> {
        let promise = Promise<IAPResult>.pending()
        let objcPromise = promise.then { (result: IAPResult) -> ObjCIAPResult in
            ObjCIAPResult.from(iapResult: result)
        }
        
        do {
            let appStoreProduct = try AppStoreProduct.from(skProduct: skProduct)
            self.store.send(.iap(.purchase(
                IAPPurchasableProduct.subscription(product: appStoreProduct, promise: promise)
                )))
            
        } catch {
            self.feedbackLogger.fatalError(
                "Unknown subscription product identifier '\(skProduct.productIdentifier)'")
        }
        
        return objcPromise.asObjCPromise()
    }
    
    @objc func onAdPresentationStatusChange(_ presenting: Bool) {
        self.store.send(.appDelegateAction(.adPresentationStatus(presenting: presenting)))
    }
    
    @objc func getAppStoreSubscriptionProductIDs() -> Set<String> {
        // TODO: supported product ID's should be accessed from the AppState environment.
        return SupportedAppStoreProductIDs.subscription().values
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
        
        syncedVPNState.zip(with: subscription)
            .map {
                SwitchedVPNStartStopIntent.make(fromProviderManagerState: $0.0,
                                                subscriptionStatus: $0.1)
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
        let promise = Promise<VPNConfigInstallResultWrapper>.pending()
        
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
            case 1:
                self.store.send(vpnAction: .reinstallVPNConfig)
            default:
                switch indexed.value {
                case .nonLoaded, .noneStored:
                    self.feedbackLogger.fatalError("Unexpected value '\(indexed.value)'")
                case .loaded(_):
                    promise.fulfill(.init(.installedSuccessfully))
                case .error(let errorEvent):
                    if case .failedConfigLoadSave(let error) = errorEvent.error {
                        if error.configurationReadWriteFailedPermissionDenied {
                            promise.fulfill(.init(.permissionDenied))
                        } else {
                            promise.fulfill(.init(.otherError))
                        }
                    }
                }
            }
        }
        
        return promise.asObjCPromise()
    }
}
