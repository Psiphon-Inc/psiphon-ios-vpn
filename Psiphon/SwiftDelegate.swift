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

enum AppDelegateAction {
    case appDidLaunch(psiCashData: PsiCashLibData)
    case appEnteredForeground
}

struct AppDelegateReducerState: Equatable {
    var psiCashBalance: PsiCashBalance
    var psiCash: PsiCashState
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
        
    case .appEnteredForeground:
        return [ environment.psiCashStore(.refreshPsiCashState).mapNever() ]
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
        self.psiCashLib = PsiCash()
        
        self.store = Store(
            initialValue: AppState(),
            reducer: makeAppReducer(),
            environment: { [unowned self] store in
                let (environment, cleanup) = makeEnvironment(
                    store: store,
                    vpnStatus: VPNStatusBridge.instance.$status,
                    psiCashLib: self.psiCashLib,
                    objcBridgeDelegate: objcBridge,
                    rewardedVideoAdBridgeDelegate: self
                )
                self.environmentCleanup = cleanup
                return environment
        })
        
        self.store.send(
            .appDelegateAction(.appDidLaunch(psiCashData: self.psiCashLib.dataModel()))
        )
        
        // Maps connected events to refresh state messages sent to store.
        self.lifetime += VPNStatusBridge.instance.$status.signalProducer
            .skipRepeats()
            .filter { $0 == .connected }
            .map(value: AppAction.psiCash(.refreshPsiCashState))
            .send(store: self.store)
        
        // Forwards `PsiCashState` updates to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.balanceState)
            .startWithValues { [unowned objcBridge] balanceViewModel in
                objcBridge.onPsiCashBalanceUpdate(.init(swiftState: balanceViewModel))
        }
        
        // Forwards `SubscriptionStatus` updates to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer.map(\.subscription.status)
            .startWithValues { [unowned objcBridge] in
                objcBridge.onSubscriptionStatus(BridgedUserSubscription.from(state: $0))
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

    }
    
    @objc func applicationWillEnterForeground(_ application: UIApplication) {
        self.store.send(.appDelegateAction(.appEnteredForeground))
    }
    
    @objc func applicationWillTerminate(_ application: UIApplication) {
        self.environmentCleanup?()
    }
    
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
            vpnStatusSignal: VPNStatusBridge.instance.$status.signalProducer
        )
    }
    
    @objc func getCustomRewardData(_ callback: @escaping (CustomData?) -> Void) {
        callback(PsiCashEffect(psiCash: self.psiCashLib).rewardedVideoCustomData())
    }
    
    @objc func resetLandingPage() {
        self.store.send(.landingPage(.reset))
    }
    
    @objc func showLandingPage() {
        self.store.send(.landingPage(.openRandomlySelectedLandingPage))
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
            fatalError("Unknown subscription product identifier '\(product.productIdentifier)'")
        }
        
        return objcPromise.asObjCPromise()
    }
    
}
