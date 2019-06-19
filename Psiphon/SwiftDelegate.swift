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
import SwiftActors
import ReactiveSwift
import Promises
import StoreKit

// TODO: `self.app` is force unwrapped multiple times in this file.

// Represents actions that are sent from ObjC and result in an effect in `appDelegateReducer`.
enum ObjcEffectAction {
    case appForegrounded
    case landingPage(LandingPageAction)
    case iapStore(IAPAction)
}

typealias LandingPageAction = LandingPageActor.Action
typealias IAPAction = IAPActor.Action

func appDelegateReducer(
    state: inout UIState, action: AppAction
) -> [EffectType<AppAction, Application.ExternalAction>] {
    switch action {

    case .objcEffectAction(let objcAction):
        switch objcAction {
        case .appForegrounded:
            return [.external(.action(.psiCash(.refreshState(reason: .appForegrounded, promise: nil))))]

        case let .landingPage(.open(url)):
            return [.external(.action(.landingPage(.open(url))))]

        case let .iapStore(.refreshReceipt(promise)):
            return [.external(.action(.inAppPurchase(.refreshReceipt(promise))))]

        case let .iapStore(.buyProduct(product, promise)):
            return [.external(.action(.inAppPurchase(.buyProduct(product, promise))))]

        case .landingPage(.reset):
            return [.external(.action(.landingPage(.reset)))]

        case .iapStore(.verifiedConsumableTransaction(_)):
            // TODO: This action should be made private to actors only.
            fatalError()
        }

    default:
        return []
    }

}

// MARK: SwiftAppDelegate
@objc final class SwiftDelegate: NSObject {

    static let instance = SwiftDelegate()
    private var (lifetime, token) = Lifetime.make()
    private var objcBridge: ObjCBridgeDelegate!
    private var app: Application?

}

// MARK: Bridge API

extension SwiftDelegate: RewardedVideoAdBridgeDelegate {
    func adPresentationStatus(_ status: AdPresentation) {
        self.app!.store.send(.psiCash(.rewardedVideoPresentation(status)))
    }

    func adLoadStatus(_ status: AdLoadStatus) {
        self.app!.store.send(.psiCash(.rewardedVideoLoad(status)))
    }
}

// API exposed to ObjC.
extension SwiftDelegate: SwiftBridgeDelegate {

    @objc static var bridge: SwiftBridgeDelegate {
        return SwiftDelegate.instance
    }

    @objc func set(objcBridge: ObjCBridgeDelegate) {
        self.objcBridge = objcBridge
    }

    @objc func applicationDidFinishLaunching(_ application: UIApplication) {
        let reducer: Reducer<UIState, AppAction, Application.ExternalAction>
        if Current.debugging.printStoreLogs {
            reducer = logging(appReducer)
        } else {
            reducer = appReducer
        }
        self.app = Application(initialValue: .init(psiCash: PsiCashState()),
                               reducer: reducer,
                               objcEffectHandler: { [unowned self] objAction in
                                switch objAction {
                                case .presentRewardedVideoAd(let customData):
                                    self.objcBridge.presentRewardedVideoAd(customData: customData,
                                                                           delegate: self)
                                case .connectTunnel:
                                    Current.vpnManager.startTunnel()
                                case .dismiss(let screen):
                                    self.objcBridge.dismiss(screen: screen)
                                }})

        self.lifetime += self.app!.actorOutput.map(\.subscription)
            .startWithValues { [unowned self] in
                self.objcBridge.onSubscriptionStatus(BridgedUserSubscription.from(state: $0))
        }

        self.lifetime += self.app!.actorOutput.map(\.psiCash?)
            .startWithValues { [unowned self] in
                guard let balanceState = $0?.balanceState else {
                    return
                }
                self.objcBridge.onPsiCashBalanceUpdate(.init(swiftBalanceState: balanceState))
        }

        self.lifetime += self.app!.actorOutput.map(\.psiCash?.libData.activePurchases.items)
            .startWithValues { [unowned self] (purchased: [PsiCashPurchasedType]?) in
                let expiry: Date?
                let maybeSpeedBoost = purchased?.compactMap({ $0.speedBoost })[maybe: 0]
                if let speedBoostProduct = maybeSpeedBoost {
                    expiry = speedBoostProduct.transaction.localTimeExpiry
                } else {
                    expiry = nil
                }

                self.objcBridge.onSpeedBoostActivePurchase(expiry)
        }
    }

    @objc func applicationWillEnterForeground(_ application: UIApplication) {
        self.app!.store.send(.objcEffectAction(.appForegrounded))
    }

    @objc func createPsiCashViewController() -> UIViewController? {
        PsiCashViewController(
            store: app!.store.projection(
                value: { $0.psiCash },
                action: { .psiCash($0) },
                external: { $0 }),
            actorStateSignal: app!.actorOutput.map(\.psiCash)
        )
    }

    @objc func getCustomRewardData(_ callback: @escaping (CustomData?) -> Void) {
        let promise = Promise<CustomData?>.pending()
        self.app!.appRoot.actor?.tell(message:
            .psiCash(.rewardedVideoCustomData(promise)))
        promise.then {
            callback($0)
        }
    }

    @objc func resetLandingPage() {
        self.app!.store.send(.objcEffectAction(.landingPage(.reset)))
    }

    @objc func showLandingPage() {
        guard let landingPages = Current.sharedDB.getHomepages(), landingPages.count > 0 else {
            return
        }
        let randomURL = landingPages.randomElement()!.url

        let restrictedURL = RestrictedURL(value: randomURL) { (env: Environment) -> Bool in
            return env.tunneled
        }

        self.app!.store.send(.objcEffectAction(.landingPage(.open(restrictedURL))))
    }

    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError> {
        let promise = Promise<Result<(), SystemErrorEvent>>.pending()
        let objcPromise = promise.then { result -> Error? in
            return result.projectError()?.error
        }
        self.app!.store.send(.objcEffectAction(.iapStore(.refreshReceipt(promise))))
        return objcPromise.asObjCPromise()
    }

    @objc func buyAppStoreSubscriptionProduct(
        _ product: SKProduct
    ) -> Promise<ObjCIAPResult>.ObjCPromise<ObjCIAPResult> {
        let promise = Promise<IAPResult>.pending()
        let objcPromise = promise.then { (result: IAPResult) -> ObjCIAPResult in
            ObjCIAPResult.from(iapResult: result)
        }

        if let purchasable = AppStoreProduct(product) {
            self.app!.store.send(.objcEffectAction(.iapStore(.buyProduct(
                PurchasableProduct.subscription(product: purchasable), promise))))
        } else {
            fatalError("Unknown subscription product identifier '\(product.productIdentifier)'")
        }

        return objcPromise.asObjCPromise()
    }

}
