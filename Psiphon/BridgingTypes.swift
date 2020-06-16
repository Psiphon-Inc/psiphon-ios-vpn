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
import PsiApi
import AppStoreIAP
import PsiCashClient

// MARK: Bridge Protocols

/// Interface for AppDelegate functionality implemented in Swift and called from ObjC.
@objc protocol RewardedVideoAdBridgeDelegate {
    func adPresentationStatus(_ status: AdPresentation)
    func adLoadStatus(_ status: AdLoadStatus, error: NSError?)
}

/// ObjC-Swift interface. Functionality implemented in ObjC and called from Swift.
/// All Delegate functions are called on the main thread.
@objc protocol ObjCBridgeDelegate {
    
    @objc func startStopVPNWithInterstitial()
    
    @objc func onPsiCashBalanceUpdate(_ balance: BridgedBalanceViewBindingType)

    /// Called with latest active Speed Boost expiry time.
    /// If no Speed Boost purchase exists, or if it has already expired, delegate is called
    /// with nil value.
    @objc func onSpeedBoostActivePurchase(_ expiryTime: Date?)

    @objc func onSubscriptionStatus(_ status: BridgedUserSubscription)
    
    @objc func onSubscriptionBarViewStatusUpdate(_ status: ObjcSubscriptionBarViewState)
    
    @objc func onVPNStatusDidChange(_ status: VPNStatus)
    
    @objc func onVPNStartStopStateDidChange(_ status: VPNStartStopStatus)
    
    @objc func onVPNStateSyncError(_ userErrorMessage: String)
    
    @objc func onReachabilityStatusDidChange(_ previousStats: ReachabilityStatus)

    @objc func dismiss(screen: DismissibleScreen, completion: (() -> Void)?)

    @objc func presentUntunneledRewardedVideoAd(customData: CustomData,
                                                delegate: RewardedVideoAdBridgeDelegate)
    
    @objc func presentSubscriptionIAPViewController()
}

/// Interface for AppDelegate functionality implemented in Swift and called from ObjC.
@objc protocol SwiftBridgeDelegate {
    @objc static var bridge: SwiftBridgeDelegate { get }
    
    // UIApplicationDelegate callbacks
    
    @objc func applicationDidFinishLaunching(_ application: UIApplication,
                                             objcBridge: ObjCBridgeDelegate)
    @objc func applicationWillEnterForeground(_ application: UIApplication)
    @objc func applicationDidEnterBackground(_ application: UIApplication)
    @objc func applicationDidBecomeActive(_ application: UIApplication)
    @objc func applicationWillTerminate(_ application: UIApplication)
    
    // -
    
    @objc func makeSubscriptionBarView() -> SubscriptionBarView
    
    @objc func makePsiCashViewController(
        _ initialTab: PsiCashViewController.Tabs
    ) -> UIViewController?
    @objc func getCustomRewardData(_ callback: @escaping (String?) -> Void)
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError>
    @objc func buyAppStoreSubscriptionProduct(
        _ skProduct: SKProduct
    ) -> Promise<ObjCIAPResult>.ObjCPromise<ObjCIAPResult>
    @objc func onAdPresentationStatusChange(_ presenting: Bool)
    @objc func getAppStoreSubscriptionProductIDs() -> Set<String>
    @objc func getAppStateFeedbackEntry(completionHandler: @escaping (String) -> Void)
    @objc func isCurrentlySpeedBoosted(completionHandler: @escaping (Bool) -> Void)
    
    // VPN
    
    @objc func switchVPNStartStopIntent()
        -> Promise<SwitchedVPNStartStopIntent>.ObjCPromise<SwitchedVPNStartStopIntent>
    @objc func sendNewVPNIntent(_ value: SwitchedVPNStartStopIntent)
    @objc func restartVPNIfActive()
    @objc func syncWithTunnelProvider(reason: TunnelProviderSyncReason)
    @objc func reinstallVPNConfig()
    @objc func installVPNConfigWithPromise()
        -> Promise<VPNConfigInstallResultWrapper>.ObjCPromise<VPNConfigInstallResultWrapper>
}

// MARK: Bridged Types

@objc enum StartButtonAction: Int {
    case startTunnelWithoutAds
    case startTunnelWithAds
    case stopVPN
}

// TODO: Log the fatalError calls
@objc final class SwitchedVPNStartStopIntent: NSObject {
    
    let switchedIntent: TunnelStartStopIntent
    @objc var startButtonAction: StartButtonAction
    
    private init(
        switchedIntent: TunnelStartStopIntent,
        startButtonAction: StartButtonAction
    ) {
        self.switchedIntent = switchedIntent
        self.startButtonAction = startButtonAction
    }
    
    @objc func forceNoAds() {
        if case .startTunnelWithAds = startButtonAction {
            startButtonAction = .startTunnelWithoutAds
        }
    }
    
    static func make<T: TunnelProviderManager>(
        fromProviderManagerState state: VPNProviderManagerState<T>,
        subscriptionStatus: SubscriptionStatus,
        currentActiveSpeedBoost: PurchasedExpirableProduct<SpeedBoostProduct>?
    ) -> SwitchedVPNStartStopIntent {
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

        let intendToStart: Bool
        let newIntent: TunnelStartStopIntent
        if state.vpnStatus.providerRunning {
            newIntent = .stop
            intendToStart = false
        } else {
            newIntent = .start(transition: .none)
            intendToStart = true
        }
        
        let startButtonAction: StartButtonAction
        if (intendToStart) {
            if (state.loadState.vpnConfigurationInstalled) {
                // If user is subscribed, or there currently is an active speed boost,
                // then start tunnel without ads.
                if (userSubscribed || currentActiveSpeedBoost != nil) {
                    startButtonAction = .startTunnelWithoutAds
                } else {
                    startButtonAction = .startTunnelWithAds
                }
            } else {
                // VPN Config is not installed. Skip ads.
                startButtonAction = .startTunnelWithoutAds
            }
        } else {
            // The intent is to stop the VPN.
            startButtonAction = .stopVPN
        }
        
        return SwitchedVPNStartStopIntent(
            switchedIntent: newIntent,
            startButtonAction: startButtonAction
        )
    }
    
}

/// Bridging type with a simpler representation of `AppState.vpnState.value.startStopState`.
@objc enum VPNStartStopStatus: Int {
    case none
    case pendingStart
    case startFinished
    case failedUserPermissionDenied
    case failedOtherReason
    case internetNotReachable
    
    static func from(startStopState: VPNStartStopStateType) -> Self {
        switch startStopState {
            case .pending(.startPsiphonTunnel):
                return .pendingStart
            case .completed(.success(.startPsiphonTunnel)):
                return .startFinished
            case .completed(.failure(let errorEvent)):
                switch errorEvent.error {
                case .neVPNError(let neVPNError):
                    if neVPNError.configurationReadWriteFailedPermissionDenied {
                        return .failedUserPermissionDenied
                    } else {
                        return .failedOtherReason
                    }
                case .internetNotReachable:
                    return .internetNotReachable
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
    @objc let hasBeenInIntroPeriod: Bool

    init(_ state: BridgedSubscriptionState, _ subscription: SubscriptionIAPPurchase?) {
        self.state = state
        self.latestExpiry = subscription?.expires
        self.hasBeenInIntroPeriod = subscription?.hasBeenInIntroOfferPeriod ?? false
    }

    static func from(state: SubscriptionStatus) -> BridgedUserSubscription {
        switch state {
        case .subscribed(let purchase):
            return .init(.active, purchase)
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
