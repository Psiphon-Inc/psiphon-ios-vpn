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
    var receiptData: ReceiptData?
}

func appDelegateReducer(
    state: inout AppDelegateReducerState, action: AppDelegateAction
) -> [Effect<AppDelegateAction>] {
    switch action {
    case .appDidLaunch(psiCashData: let libData):
        state.psiCash.appDidLaunch(libData)
        state.psiCashBalance = .fromStoredExpectedReward(libData: libData)
        return [
            Current.psiCashEffect.expirePurchases().mapNever(),
            Current.paymentQueue.addObserver(Current.paymentTransactionDelegate).mapNever(),
            .fireAndForget {
                Current.app.store.send(.appReceipt(.localReceiptRefresh))
            }
        ]
        
    case .appEnteredForeground:
        return [
            .fireAndForget {
                Current.app.store.send(.psiCash(.refreshPsiCashState))
            }
        ]
    }
    
}

// MARK: SwiftAppDelegate
@objc final class SwiftDelegate: NSObject {
    
    static let instance = SwiftDelegate()
    private var (lifetime, token) = Lifetime.make()
    
}

// MARK: Bridge API

extension SwiftDelegate: RewardedVideoAdBridgeDelegate {
    func adPresentationStatus(_ status: AdPresentation) {
        Current.app.store.send(.psiCash(.rewardedVideoPresentation(status)))
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
        Current.app.store.send(.psiCash(.rewardedVideoLoad(loadResult)))
    }
}

// API exposed to ObjC.
extension SwiftDelegate: SwiftBridgeDelegate {
    
    @objc static var bridge: SwiftBridgeDelegate {
        return SwiftDelegate.instance
    }
    
    @objc func set(objcBridge: ObjCBridgeDelegate) {
        Current.objcBridgeDelegate = objcBridge
    }
    
    @objc func applicationDidFinishLaunching(_ application: UIApplication) {
        if Debugging.printAppState {
            self.lifetime += Current.app.store.$value.signalProducer.startWithValues { appState in
                let path = \AppState.iapState.purchasing
                print("*", "AppState Path \(path)")
                print("*", String(describing: appState[keyPath: path]))
                print("*", "-----")
            }
        }
        
        Current.app.store.send(
            .appDelegateAction(.appDidLaunch(psiCashData: Current.psiCashEffect.libData))
        )
        
        // Maps connected events to refresh state messages sent to store.
        self.lifetime += Current.vpnStatus.signalProducer
            .skipRepeats()
            .filter { $0 == .connected }
            .map(value: AppAction.psiCash(.refreshPsiCashState))
            .send(store: Current.app.store)
        
        // Forwards `PsiCashState` updates to ObjCBridgeDelegate.
        self.lifetime += Current.app.store.$value.signalProducer
            .map(\.balanceState)
            .startWithValues { balanceViewModel in
                guard let bridge = Current.objcBridgeDelegate else { fatalError() }
                bridge.onPsiCashBalanceUpdate(.init(swiftState: balanceViewModel))
        }
        
        // Forwards `SubscriptionStatus` updates to ObjCBridgeDelegate.
        self.lifetime += Current.app.store.$value.signalProducer.map(\.subscription.status)
            .startWithValues {
                guard let bridge = Current.objcBridgeDelegate else { fatalError() }
                bridge.onSubscriptionStatus(BridgedUserSubscription.from(state: $0))
        }
        
        // Forewards SpeedBoost purchase expiry date (if the user is not subscribed)
        // to ObjCBridgeDelegate.
        self.lifetime += Current.app.store.$value.signalProducer
            .map { appState -> Date? in
                if case .subscribed(_) = appState.subscription.status {
                    return nil
                } else {
                    return appState.psiCash.activeSpeedBoost?.transaction.localTimeExpiry
                }
        }
        .skipRepeats()
        .startWithValues{ speedBoostExpiry in
            guard let bridge = Current.objcBridgeDelegate else { fatalError() }
            bridge.onSpeedBoostActivePurchase(speedBoostExpiry)
        }

    }
    
    @objc func applicationWillEnterForeground(_ application: UIApplication) {
        Current.app.store.send(.appDelegateAction(.appEnteredForeground))
    }
    
    @objc func applicationWillTerminate(_ application: UIApplication) {
        let _ = Current.paymentQueue.removeObserver(Current.paymentTransactionDelegate).wait()
    }
    
    @objc func createPsiCashViewController() -> UIViewController? {
        PsiCashViewController(
            store: Current.app.store.projection(
                value: { $0.psiCashViewController },
                action: { .psiCash($0) }),
            iapStore: Current.app.store.projection(
                value: erase,
                action: { .iap($0) }),
            productRequestStore: Current.app.store.projection(
                value: erase,
                action: { .productRequest($0) } )
        )
    }
    
    @objc func getCustomRewardData(_ callback: @escaping (CustomData?) -> Void) {
        callback(Current.psiCashEffect.rewardedVideoCustomData())
    }
    
    @objc func resetLandingPage() {
        Current.app.store.send(.landingPage(.reset))
    }
    
    @objc func showLandingPage() {
        guard let landingPages = Current.sharedDB.getHomepages(), landingPages.count > 0 else {
            return
        }
        let randomURL = landingPages.randomElement()!.url
        
        let restrictedURL = RestrictedURL(value: randomURL) { (env: Environment) -> Bool in
            return env.tunneled
        }
        Current.app.store.send(.landingPage(.open(restrictedURL)))
    }
    
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError> {
        let promise = Promise<Result<(), SystemErrorEvent>>.pending()
        let objcPromise = promise.then { result -> Error? in
            return result.projectError()?.error
        }
        Current.app.store.send(.appReceipt(.remoteReceiptRefresh(optinalPromise: promise)))
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
            Current.app.store.send(.iap(.purchase(
                IAPPurchasableProduct.subscription(product: appStoreProduct, promise: promise)
                )))
            
        } catch {
            fatalError("Unknown subscription product identifier '\(product.productIdentifier)'")
        }
        
        return objcPromise.asObjCPromise()
    }
    
}
