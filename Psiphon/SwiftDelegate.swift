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
    userConfigs: UserDefaultsConfig,
    sharedDB: PsiphonDataSharedDB,
    psiCashEffects: PsiCashEffect,
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
        state.psiCashBalance = .fromStoredExpectedReward(libData: libData,
                                                         userConfigs: environment.userConfigs)
        return [
            environment.psiCashEffects.expirePurchases(sharedDB: environment.sharedDB).mapNever(),
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
    
    private var (lifetime, token) = Lifetime.make()
    private var store: Store<AppState, AppAction>!
    private var psiCashLib: PsiCash!
    private var environmentCleanup: (() -> Void)?
    
}

// MARK: Bridge API

extension SwiftDelegate: RewardedVideoAdBridgeDelegate {
    func adPresentationStatus(_ status: AdPresentation) {
        self.store.send(.psiCash(.rewardedVideoPresentation(status)))
    }
    
    func adLoadStatus(_ status: AdLoadStatus, error: SystemError?) {
        let loadResult: RewardedVideoLoad
        if let error = error {
            // Note that error event is created here as opposed to the origin
            // of where the error occured. However this is acceptable as long as
            // this function is called once for each error that happened almost immediately.
            loadResult = .failure(ErrorEvent(.systemError(error)))
        } else {
            if case .error = status {
                loadResult = .failure(ErrorEvent(ErrorRepr(repr: "Ad failed to load")))
            } else {
                loadResult = .success(status)
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
            reducer: makeAppReducer(),
            environment: { [unowned self] store in
                let (environment, cleanup) = makeEnvironment(
                    store: store,
                    psiCashLib: self.psiCashLib,
                    objcBridgeDelegate: objcBridge,
                    rewardedVideoAdBridgeDelegate: self
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
        
        // Forwards VPN status changes to ObjCBridgeDelegaet.
        self.lifetime += self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] in
                objcBridge.onVPNStatusDidChange($0)
            }
        
        // Forwards VPN state `providerSyncResult` error values, for a maximum of 5 emissions.
        // Errors are debounced for time interval defined in `VPNHardCodedValues`.
        self.lifetime += self.store.$value.signalProducer
            .map(\.vpnState.value.providerSyncResult)
            .skipRepeats()
            .compactMap { syncResult -> ErrorEvent<TunnelProviderSyncedState.SyncError>? in
                guard case let .completed(.some(syncErrorEvent)) = syncResult else {
                    return nil
                }
                return syncErrorEvent
            }
            .debounce(VPNHardCodedValues.syncStateErrorDebounceInterval, on: QueueScheduler.main)
            .take(first: 5)
            .startWithValues { [unowned objcBridge] syncErrorEvent in
                let message = """
                \(UserStrings.Tunnel_provider_sync_failed_reinstall_config())
                
                (\(String(describing: syncErrorEvent.error)))
                """
                objcBridge.onVPNStateSyncError(message)
            }
        
        // Forewards SpeedBoost purchase expiry date (if the user is not subscribed)
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
        
        // Opens landing page whenever Psiphon tunnel is connected, with
        // change in value of `VPNState` tunnel intent.
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
                dump(appState[keyPath: \.vpnState])
                print("*", "-----")
            }
        }

    }
    
    struct Changed<Value> {
        let changed: Bool
        let value: Value
    }
    
    @objc func applicationWillEnterForeground(_ application: UIApplication) {
        self.store.send(vpnAction: .syncWithProvider(reason: .appEnteredForeground))
        self.store.send(.psiCash(.refreshPsiCashState))
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
                .map(\.vpnState.value.providerVPNStatus.tunneled)
        )
    }
    
    @objc func getCustomRewardData(_ callback: @escaping (CustomData?) -> Void) {
        callback(PsiCashEffect(psiCash: self.psiCashLib).rewardedVideoCustomData())
    }
    
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError> {
        let promise = Promise<Result<(), SystemErrorEvent>>.pending()
        let objcPromise = promise.then { result -> Error? in
            return result.projectError()?.error
        }
        self.store.send(.appReceipt(.remoteReceiptRefresh(optinalPromise: promise)))
        return objcPromise.asObjCPromise()
    }
    
    @objc func buyAppStoreSubscriptionProduct(
        _ product: SKProduct
    ) -> Promise<ObjCIAPResult>.ObjCPromise<ObjCIAPResult> {
        let promise = Promise<IAPResult>.pending()
        let objcPromise = promise.then { (result: IAPResult) -> ObjCIAPResult in
            ObjCIAPResult.from(iapResult: result)
        }
        
        do {
            let appStoreProduct = try AppStoreProduct(product)
            self.store.send(.iap(.purchase(
                IAPPurchasableProduct.subscription(product: appStoreProduct, promise: promise)
                )))
            
        } catch {
            fatalErrorFeedbackLog("Unknown subscription product identifier '\(product.productIdentifier)'")
        }
        
        return objcPromise.asObjCPromise()
    }
    
    @objc func onAdPresentationStatusChange(_ presenting: Bool) {
        self.store.send(.appDelegateAction(.adPresentationStatus(presenting: presenting)))
    }
    
    @objc func getAppStoreSubscriptionProductIDs() -> Set<String> {
        let productIds = StoreProductIds.subscription()
        return productIds.values
    }
    
    @objc func getAppStateFeedbackEntry(completionHandler: @escaping (String) -> Void) {
        self.store.$value.signalProducer
            .take(first: 1)
            .startWithValues { appState in
                completionHandler("""
                    ContainerInfo: {
                    \"AppState\":\"\(makeFeedbackEntry(appState))\",
                    \"UserDefaultsConfig\":\"\(makeFeedbackEntry(UserDefaultsConfig()))\"
                    }
                    """)
        }
    }
    
    @objc func swithVPNStartStopIntent()
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
            self.store.send(vpnAction: .tunnelStateIntent(.start(transition: .none)))
        case .stop:
            self.store.send(vpnAction: .tunnelStateIntent(.stop))
        default:
            fatalErrorFeedbackLog("Unexpected state '\(value.switchedIntent)'")
        }
    }
    
    @objc func restartVPNIfActive() {
        self.store.send(vpnAction: .tunnelStateIntent(.start(transition: .restart)))
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
        }.flatMap(.latest) { indexed -> SignalProducer<IndexedPsiphonTPMLoadState, Never> in
            
            // Index 1 represents the value of ProviderManagerLoadState before
            // `.reinstallVPNConfig` action is sent.
            
            switch indexed.index {
            case 0:
                fatalErrorFeedbackLog("Unexpected index 0")
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
        .startWithValues { [promise, unowned store] indexed in
            switch indexed.index {
            case 0:
                fatalErrorFeedbackLog("Unexpected index 0")
            case 1:
                store!.send(vpnAction: .reinstallVPNConfig)
            default:
                switch indexed.value {
                case .nonLoaded, .noneStored:
                    fatalErrorFeedbackLog("Unepxected value '\(indexed.value)'")
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
