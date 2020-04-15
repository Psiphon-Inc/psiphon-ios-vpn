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
    func adLoadStatus(_ status: AdLoadStatus, error: SystemError?)
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
    
    @objc func onVPNStatusDidChange(_ status: VPNStatus)
    
    @objc func onVPNStartStopStateDidChange(_ status: VPNStartStopStatus)
    
    @objc func onVPNStateSyncError(_ userErrorMessage: String)

    @objc func dismiss(screen: DismissableScreen)

    @objc func presentRewardedVideoAd(customData: CustomData,
                                      delegate: RewardedVideoAdBridgeDelegate)
}

/// Inteface for AppDelegate functionality implemented in Swift and called from ObjC.
@objc protocol SwiftBridgeDelegate {
    @objc static var bridge: SwiftBridgeDelegate { get }
    
    // UIApplicationDelegate callbacks
    
    @objc func applicationDidFinishLaunching(_ application: UIApplication,
                                             objcBridge: ObjCBridgeDelegate)
    @objc func applicationWillEnterForeground(_ application: UIApplication)
    @objc func applicationDidBecomeActive(_ application: UIApplication)
    @objc func applicationWillTerminate(_ application: UIApplication)
    
    // -
    
    @objc func createPsiCashViewController(
        _ initialTab: PsiCashViewController.Tabs
    ) -> UIViewController?
    @objc func getCustomRewardData(_ callback: @escaping (String?) -> Void)
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError>
    @objc func buyAppStoreSubscriptionProduct(
        _ product: SKProduct
    ) -> Promise<ObjCIAPResult>.ObjCPromise<ObjCIAPResult>
    @objc func onAdPresentationStatusChange(_ presenting: Bool)
    @objc func getAppStoreSubscriptionProductIDs() -> Set<String>
    
    // VPN
    
    @objc func swithVPNStartStopIntent()
        -> Promise<SwitchedVPNStartStopIntent>.ObjCPromise<SwitchedVPNStartStopIntent>
    @objc func sendNewVPNIntent(_ value: SwitchedVPNStartStopIntent)
    @objc func restartVPNIfActive()
    @objc func syncWithTunnelProvider(reason: TunnelProviderSyncReason)
    @objc func reinstallVPNConfig()
    @objc func installVPNConfigWithPromise()
        -> Promise<VPNConfigInstallResultWrapper>.ObjCPromise<VPNConfigInstallResultWrapper>
}

// MARK: Bridged Types

@objc final class SwitchedVPNStartStopIntent: NSObject {
    
    let switchedIntent: TunnelStartStopIntent
    @objc let vpnConfigInstalled: Bool
    @objc let userSubscribed: Bool
    
    @objc var intendToStart: Bool {
        switch switchedIntent {
        case .start(transition: .none): return true
        case .stop: return false
        default: fatalError()
        }
    }
    
    private init(switchedIntent: TunnelStartStopIntent, vpnConfigInstalled: Bool,
                 userSubscribed: Bool) {
        self.switchedIntent = switchedIntent
        self.vpnConfigInstalled = vpnConfigInstalled
        self.userSubscribed = userSubscribed
    }
    
    static func make<T: TunnelProviderManager>(
        fromProviderManagerState state: VPNProviderManagerState<T>,
        subscriptionStatus: SubscriptionStatus
    ) -> Self {
        guard case .completed(_) = state.providerSyncResult else {
            fatalError("expected no pending sync with tunnel provider")
        }
        
        let userSubscribed: Bool
        switch subscriptionStatus {
        case .subscribed(_):
            userSubscribed = true
        case .notSubscribed:
            userSubscribed = false
        case .unknown:
            fatalError("expected subscription status to not be unknown")
        }
        
        switch state.tunnelIntent {
        case .start(transition: _):
            return .init(switchedIntent: .stop,
                         vpnConfigInstalled: state.loadState.vpnConfigurationInstalled,
                         userSubscribed: userSubscribed)
        case .stop, .none:
            return .init(switchedIntent: .start(transition: .none),
                         vpnConfigInstalled: state.loadState.vpnConfigurationInstalled,
                         userSubscribed: userSubscribed)
        }
    }
    
}

/// Bridging type with a simpler representation of `AppState.vpnState.value.startStopState`.
@objc enum VPNStartStopStatus: Int {
    case none
    case pendingStart
    case startFinished
    case failedUserPermissionDenied
    case failedOtherReason
    
    static func from(startStopState: VPNStartStopStateType) -> Self {
        switch startStopState {
            case .pending(.startPsiphonTunnel):
                return .pendingStart
            case .completed(.success(.startPsiphonTunnel)):
                return .startFinished
            case .completed(.failure(let errorEvent)):
                if errorEvent.error.configurationReadWriteFailedPermissionDenied {
                    return .failedUserPermissionDenied
                } else {
                    return .failedOtherReason
                }
            default:
                return .none
        }
    }
    
}

/// Bridging type representing result of installing VPN configuration.

@objc enum VPNConfigInstallResult: Int {
    case installedSuccessfully
    case permissionDenied
    case otherError
}

@objc final class VPNConfigInstallResultWrapper: NSObject {
    @objc let value: VPNConfigInstallResult
    init(_ value: VPNConfigInstallResult) {
        self.value = value
    }
}

@objc final class VPNStateCompat: NSObject {
    
    @objc static func providerNotStopped(_ value: TunnelProviderVPNStatus) -> Bool {
        return value.providerNotStopped
    }
    
    @objc static func providerNotStopped(vpnStatus value: VPNStatus) -> Bool {
        return value.providerNotStopped
    }
}

// `SubscriptionState` case only bridged to ObjC compatible type.
@objc enum BridgedSubscriptionState: Int {
    case unknown
    case active
    case inactive
}

// `SubscriptionState` with associated value bridged to ObjC compatible type.
@objc final class BridgedUserSubscription: NSObject {
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

    static func from(state: SubscriptionStatus) -> BridgedUserSubscription {
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
@objc final class BridgedBalanceViewBindingType: NSObject {
    let state: PsiCashBalanceView.BindingType

    init(swiftState state: PsiCashBalanceView.BindingType) {
        self.state = state
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
        return ObjCIAPResult(transaction: iapResult.transaction,
                             error: iapResult.result.projectError())
    }
}
