/*
 * Copyright (c) 2020, Psiphon Inc.
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
import Promises

// MARK: Bridge Protocols

/// Interface for AppDelegate functionality implemented in Swift and called from ObjC.
@objc protocol RewardedVideoAdBridgeDelegate {
    func adPresentationStatus(_ status: AdPresentation)
    func adLoadStatus(_ status: AdLoadStatus)
}

/// ObjC-Swift interface. Functionality implemented in ObjC and called from Swift.
/// All Delegate functions are called on the main thread.
@objc protocol ObjCBridgeDelegate {
    @objc func onPsiCashBalanceUpdate(_ balance: BridgedBalanceViewBindingType)

    /// Called with latest active Speed Boost expiry time.
    /// If no Speed Boost purchase exists, or if it has already expired, delegate is called
    /// with nil value.
    @objc func onSpeedBoostActivePurchase(_ expiryTime: Date?)

    @objc func onSubscriptionStatus(_ status: BridgedUserSubscription)

    @objc func dismiss(screen: DismissableScreen)

    @objc func presentRewardedVideoAd(customData: CustomData,
                                      delegate: RewardedVideoAdBridgeDelegate)
}

/// Inteface for AppDelegate functionality implemented in Swift and called from ObjC.
@objc protocol SwiftBridgeDelegate {
    @objc static var bridge: SwiftBridgeDelegate { get }
    @objc func set(objcBridge: ObjCBridgeDelegate)
    @objc func applicationDidFinishLaunching(_ application: UIApplication)
    @objc func applicationWillEnterForeground(_ application: UIApplication)
    @objc func createPsiCashViewController() -> UIViewController?
    @objc func getCustomRewardData(_ callback: @escaping (String?) -> Void)
    @objc func resetLandingPage()
    @objc func showLandingPage()
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError>
    @objc func buyAppStoreSubscriptionProduct(
        _ product: SKProduct
    ) -> Promise<ObjCIAPResult>.ObjCPromise<ObjCIAPResult>
}

// MARK: Bridged Types

/// `NEVPNStatus` observable bridged to Swift.
@objc class VPNStatusBridge: NSObject {

    @objc static let instance = VPNStatusBridge()

    @State var status: NEVPNStatus = .invalid

    @objc func next(_ vpnStatus: NEVPNStatus) {
        DispatchQueue.main.async {
            self.status = vpnStatus
        }
    }

}

// `SubscriptionState` case only bridged to ObjC compatible type.
@objc enum BridgedSubscriptionState: Int {
    case unknown
    case active
    case inactive
}

// `SubscriptionState` with associated value bridged to ObjC compatible type.
@objc class BridgedUserSubscription: NSObject {
    @objc let state: BridgedSubscriptionState
    @objc let latestExpiry: Date?
    @objc let productId: String?
    @objc let hasBeenInIntroPeriod: Bool

    init(_ state: BridgedSubscriptionState, _ data: SubscriptionData?) {
        self.state = state
        self.latestExpiry = data?.latestExpiry
        self.productId = data?.productId
        self.hasBeenInIntroPeriod = data?.hasBeenInIntroPeriod ?? false
    }

    static func from(state: SubscriptionState) -> BridgedUserSubscription {
        switch state {
        case .subscribed(let data):
            return .init(.active, data)
        case .notSubscribed:
            return .init(.inactive, .none)
        case .unknown:
            return .init(.unknown, .none)
        }
    }

}

/// Wraps `BalanceState` struct.
@objc class BridgedBalanceViewBindingType: NSObject {
    let balanceState: BalanceState

    init(swiftBalanceState state: BalanceState) {
        self.balanceState = state
    }
}

// IAP result
@objc final class ObjCIAPResult: NSObject {
    @objc let transaction: SKPaymentTransaction?
    @objc let error: Error?

    init(transaction: SKPaymentTransaction?, error: Error?) {
        self.transaction = transaction
        self.error = error
    }

    static func from(iapResult: IAPResult) -> ObjCIAPResult {
        // `IAPError` is either set to internal `IAPActor` error,
        // or it wraps the `SKPaymenTransaction` error.
        return ObjCIAPResult(transaction: iapResult.transaction,
                             error: iapResult.result.projectError())
    }
}
