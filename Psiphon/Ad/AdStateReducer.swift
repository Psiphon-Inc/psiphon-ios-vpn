/*
 * Copyright (c) 2021, Psiphon Inc.
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
import PsiApi
import Utilities
import PsiCashClient
import AppStoreIAP
import GoogleMobileAds

/// Represent ad consent failures.
enum AdConsentError: HashableError {
    
    /// Ad consent request failed due to tunnel not being connected.
    case notUntunneled
    
    /// Ad consent request failed.
    case other(SystemError<Int>)
    
}

/// Ad SDK initialization failure type.
enum AdSdkInitError: HashableError {
    
    /// Represents an error while collecting user consent through `AdConsent`.
    case adConsentError(AdConsentError)
    
    /// Represents failure of all AdMob adapters (there is currently just one) to be in a ready state.
    case adMobSDKInitNoAdaptersReady(GADInitializationStatus)
    
}

/// Wraps `AdState` and all other immutable values used by `adStateReducer`.
struct AdReducerState: Equatable {
    var adState = AdState()
    let tunnelConnection: TunnelConnection?
}

struct AdState: Equatable {
    
    /// Status of app tracking transparency permission.
    /// Value of `nil` implies that the status has not been checked yet.
    var appTrackingTransparencyPermission: PendingResult<Utilities.Unit, AdSdkInitError>? = .none
    
    /// Represents the latest known status of the interstitial ad controller.
    var interstitialAdControllerStatus: AdMobInterstitialAdController.Status = .noAdsLoaded
    
    /// Represents the latest known status of the rewarded video ad controller.
    var rewardedVideoAdControllerStatus: AdMobRewardedVideoAdController.Status = .noAdsLoaded
    
    /// Whether or not to present the rewarded video ad that was last loaded.
    var presentRewardedVideoAdAfterLoad: Bool = false
    
}

enum AdAction: Equatable {
    
    /// Set of reasons for an interstitial load action.
    enum InterstitialLoadReason: Equatable {
        
        /// App is initialized.
        case appInitialized
        
        /// App is foregrounded or launched.
        case appForegrounded
        
        /// Tunnel has transitioned from a connected state to a disconnected state.
        case tunnelDisconnected
        
    }
    
    /// Initializes the Ad SDK(s), and collects consent if required.
    /// - Note: Ad SDKs might pre-fetch ads automatically after initialization.
    case collectConsentAndInitAdSdk
    
    case _collectConsentAndInitAdSdkResult(Result<GADInitializationStatus, AdSdkInitError>)
    
    /// Loads interstitial ad, if user is unsubscribed and tunnel is not connected.
    /// Collects consent and inits Ad SDK if not done already.
    case loadInterstitial(reason: InterstitialLoadReason)
    
    case presentInterstitial
    case interstitialAdUpdate(AdMobInterstitialAdController.Status,
                              AdMobInterstitialAdController)
    
    /// Loads rewarded video ad, if user is unsubscribed and tunnel is not connected.
    /// Collects consent and inits Ad SDK if not done already.
    case loadRewardedVideo(presentAfterLoad: Bool)
    
    case presentRewardedVideo
    
    case rewardedVideoAdUpdate(AdMobRewardedVideoAdController.Status,
                               AdMobRewardedVideoAdController)
    
    /// User earned rewarded of a rewarded video ad.
    case rewardedVideoAdUserEarnedReward
    
    case resetUserConsent
    
}

typealias AdStateEnvironment = (
    platform: Platform,
    feedbackLogger: FeedbackLogger,
    adConsent: AdConsent,
    psiCashLib: PsiCashEffects,
    psiCashStore: (PsiCashAction) -> Effect<Never>,
    tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
    adMobInterstitialAdController: AdMobInterstitialAdController,
    adMobRewardedVideoAdController: AdMobRewardedVideoAdController,
    adLoadCondition: () -> Bool,
    // TODO: Direct access to UI. This should be wrapped in an effect.
    topMostViewController: () -> UIViewController
)

func adStateReducer(
    state: inout AdReducerState, action: AdAction, environment: AdStateEnvironment
) -> [Effect<AdAction>] {
    
    switch action {
    
    case .collectConsentAndInitAdSdk:
        
        guard environment.adLoadCondition() else {
            return []
        }
        
        // There is already a pending request.
        if case .pending = state.adState.appTrackingTransparencyPermission {
            return []
        }
        
        state.adState.appTrackingTransparencyPermission = .pending
        
        return [
            collectATTConsentAndInitAdMobSDK(
                tunnelStatusSignal: environment.tunnelStatusSignal,
                adConsent: environment.adConsent,
                topMostViewController: environment.topMostViewController
            )
            .mapBothAsResult {
                ._collectConsentAndInitAdSdkResult($0)
            }
        ]
        
    case ._collectConsentAndInitAdSdkResult(let result):
        
        switch result {
        case .success(let gadInitializationStatus):
            
            state.adState.appTrackingTransparencyPermission = .completed(.success(.unit))
            
            // Logs success case.
            return [
                environment.feedbackLogger
                    .log(.info,
                         "AdMob inited: '\(gadInitializationStatus.adapterStatusesByClassName)'")
                    .mapNever()
            ]
            
        case .failure(let error):
            
            state.adState.appTrackingTransparencyPermission = .completed(.failure(error))
            
            // Logs Ad SDK init error.
            return [
                environment.feedbackLogger.log(.error, "AdMob failed to init: \(error)").mapNever()
            ]
            
        }
                
    case .loadInterstitial(reason: let reason):
        
         guard environment.adLoadCondition() else {
            return []
        }
        
        guard case .completed(.success(.unit)) = state.adState.appTrackingTransparencyPermission
        else {

            // Initializes Ad SDK, and concats `.loadInterstitial` action
            // to be tried again if a request is not already pending.
            
            if case .pending = state.adState.appTrackingTransparencyPermission {
                return []
            }
            
            state.adState.appTrackingTransparencyPermission = .pending
            
            return [
                collectATTConsentAndInitAdMobSDK(
                    tunnelStatusSignal: environment.tunnelStatusSignal,
                    adConsent: environment.adConsent,
                    topMostViewController: environment.topMostViewController
                )
                .mapBothAsResult(id)
                .flatMap(.latest, { consentResult in
                    
                    if case .success(_) = consentResult {
                        return Effect(value: ._collectConsentAndInitAdSdkResult(consentResult))
                            .concat(value: .loadInterstitial(reason: reason))
                    } else {
                        return Effect(value: ._collectConsentAndInitAdSdkResult(consentResult))
                    }
                    
                })
            ]
            
        }
        
        guard case .notConnected = state.tunnelConnection?.tunneled else {
            return []
        }
        
        switch state.adState.interstitialAdControllerStatus {
        
        // An ad request for an interstitial is submitted if any of the following are true:
        // - No ads have been loaded since app launch.
        // - Previous request failed.
        // - Previous attempt to present an ad failed (AdMob SDK error value is opaque,
        //     and does not describe the reason for failure. Therefore, we treat
        //     an ad failing to present the same as an ad load failing, which
        //     is to request for a new ad.)
        // - Previously loaded ad has been presented and dismissed.
        // Otherwise, request for loading an ad is rejected.
        
        case .noAdsLoaded,
             .loadFailed(_),
             .loadSucceeded(.failedToPresent(_)),
             .loadSucceeded(.dismissed):
            
            return [
                
                environment.feedbackLogger
                    .log(.info, "Interstitial load request. Reason: \(reason)")
                    .mapNever(),
                
                .fireAndForget {
                    environment.adMobInterstitialAdController
                        .load(adConsent: environment.adConsent)
                }
                
            ]
            
        default:
            
            return [
                environment.feedbackLogger.log(.warn, """
                    Interestitial load request rejected: \
                    '\(state.adState.interstitialAdControllerStatus)'
                    """)
                    .mapNever()
            ]
            
        }
        
    case .presentInterstitial:
        
        guard case .notConnected = state.tunnelConnection?.tunneled else {
            return []
        }
        
        guard
            case .loadSucceeded(.notPresented) = state.adState.interstitialAdControllerStatus
        else {
            return [
                environment.feedbackLogger.log(.warn, "No interstitial ad loaded").mapNever()
            ]
        }
        
        // Presents the loaded interstitial ad.
        return [
            .fireAndForget {
                environment.adMobInterstitialAdController.present(
                    fromRootViewController: environment.topMostViewController()
                )
            }
        ]
        
    case .interstitialAdUpdate(let status, _):
        
        state.adState.interstitialAdControllerStatus = status
        
        return [
            environment.feedbackLogger.log(
                .info, "Interstitial ad status: '\(status)'")
                .mapNever()
        ]
         
    case .loadRewardedVideo(let presentAfterLoad):
        
        guard environment.adLoadCondition() else {
            return []
        }
        
        guard case .completed(.success(.unit)) = state.adState.appTrackingTransparencyPermission
        else {

            // Initializes Ad SDK, and concats `.loadInterstitial` action
            // to be tried again if a request is not already pending.
            
            if case .pending = state.adState.appTrackingTransparencyPermission {
                return []
            }
            
            state.adState.appTrackingTransparencyPermission = .pending
            
            return [
                
                collectATTConsentAndInitAdMobSDK(
                    tunnelStatusSignal: environment.tunnelStatusSignal,
                    adConsent: environment.adConsent,
                    topMostViewController: environment.topMostViewController
                )
                .mapBothAsResult(id)
                .flatMap(.latest, { consentResult in
                    
                    if case .success(_) = consentResult {
                        return Effect(value: ._collectConsentAndInitAdSdkResult(consentResult))
                            .concat(value: .loadRewardedVideo(presentAfterLoad: presentAfterLoad))
                    } else {
                        return Effect(value: ._collectConsentAndInitAdSdkResult(consentResult))
                    }
                    
                })
                
            ]
            
        }
        
        guard case .notConnected = state.tunnelConnection?.tunneled else {
            return []
        }
        
        // Sets the present rewarded video after load flag.
        state.adState.presentRewardedVideoAdAfterLoad = presentAfterLoad
        
        switch state.adState.rewardedVideoAdControllerStatus {
        
        // An ad request for a rewarded video is submitted if any of the following are true:
        // - No ads have been loaded since app launch.
        // - Previous request failed.
        // - Previous attempt to present an ad failed (AdMob SDK error value is opaque,
        //     and does not describe the reason for failure. Therefore, we treat
        //     an ad failing to present the same as an ad load failing, which
        //     is to request for a new ad.)
        // - Previously loaded ad has been presented and dismissed.
        // Otherwise, request for loading an ad is rejected.
        
        case .noAdsLoaded,
             .loadFailed(_),
             .loadSucceeded(.failedToPresent(_)),
             .loadSucceeded(.dismissed):
            
            return [
                
                environment.feedbackLogger
                    .log(.info, "Rewarded video load request.")
                    .mapNever(),
                
                .fireAndForget {
                    let rewardData = environment.psiCashLib.rewardedVideoCustomData()
                    environment.adMobRewardedVideoAdController
                        .load(rewardData: rewardData, adConsent: environment.adConsent)
                }
                
            ]
            
        case .loadSucceeded(.notPresented):
            
            // Presents rewarded video ad if one is already loaded.
            if state.adState.presentRewardedVideoAdAfterLoad {
                return [
                    Effect(value: .presentRewardedVideo)
                ]
            } else {
                fallthrough
            }
            
        default:
            
            return [
                environment.feedbackLogger.log(.warn, """
                    Rewarded video load request rejected: \
                    '\(state.adState.rewardedVideoAdControllerStatus)'
                    """)
                    .mapNever()
            ]
            
        }
        
    case .presentRewardedVideo:
        
        guard case .notConnected = state.tunnelConnection?.tunneled else {
            return []
        }
        
        guard
            case .loadSucceeded(.notPresented) = state.adState.rewardedVideoAdControllerStatus
        else {
            return [
                environment.feedbackLogger.log(.warn, "No rewarded video ad loaded").mapNever()
            ]
        }
        
        // Presents the loaded rewarded video ad.
        return [
            .fireAndForget {
                environment.adMobRewardedVideoAdController.present(
                    fromRootViewController: environment.topMostViewController()
                )
            }
        ]
                
    case .rewardedVideoAdUpdate(let status, _):
        
        state.adState.rewardedVideoAdControllerStatus = status
        
        var effects = [Effect<AdAction>]()
        
        // Presents rewarded video ad automatically, if
        // present rewarded video after load flag is true.
        if state.adState.presentRewardedVideoAdAfterLoad,
           case .loadSucceeded(.notPresented) = status {
            
            state.adState.presentRewardedVideoAdAfterLoad = false
            
            effects.append(Effect(value: .presentRewardedVideo))
            
        }
        
        effects.append(
            environment.feedbackLogger.log(
                .info, "Rewarded video status: '\(status)'")
                .mapNever()
        )
        
        return effects
        
    case .rewardedVideoAdUserEarnedReward:
        
        return [
            
            environment.psiCashStore(
                .userDidEarnReward(PsiCashHardCodedValues.videoAdRewardAmount,
                                   .watchedRewardedVideo))
                .mapNever(),
            
            environment.feedbackLogger.log(.info, "User earned ad reward").mapNever()
            
        ]
        
    case .resetUserConsent:
        
        return [
            .fireAndForget {
                environment.adConsent.resetConsent()
            }
        ]
        
    }
    
}


/// Permission request for AppTrackingTransparency, and initializes AdMob SDK.
fileprivate func collectATTConsentAndInitAdMobSDK(
    tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
    adConsent: AdConsent,
    topMostViewController: @escaping () -> UIViewController
) -> SignalProducer<GADInitializationStatus, AdSdkInitError> {
    
    tunnelStatusSignal
        .take(first: 1)
        .flatMap(.latest) { vpnStatus -> SignalProducer<(), AdConsentError> in
            
            // Consent info update if VPN status is invalid or disconnected.
            switch vpnStatus {
            case .invalid, .disconnected:
                
                // UMP consentInfoUpdate.
                return SignalProducer.async { observer in

                    // Observer is called with the result of
                    // AdConsent.consentInfoUpdate(completionHandler:).
                    adConsent.consentInfoUpdate { maybeError in
                        
                        // Maps Error? to Result<(), AdConsentError>
                        let result: Result<(), AdConsentError> =
                            Optional<SystemError<Int>>.make(maybeError as NSError?)
                            .maybeToRight(())
                            .mapError { .other($0) }

                        observer(result)
                        
                    }

                }
                            
            default:
                return SignalProducer(error: .notUntunneled)
            }
            
        }
        .flatMap(.latest) { () -> SignalProducer<(), AdConsentError> in
            
            // Presents consent form if needed, only if VPN status is invalid or disconnected.
            tunnelStatusSignal
                .take(first: 1)
                .flatMap(.latest) { vpnStatus in
                    
                    switch vpnStatus {
                    case .invalid, .disconnected:
                        
                        // UMP present consent form if needed.
                        return SignalProducer.async { observer in

                            // Presents consent form.
                            adConsent.presentConsentFormIfNeeded(
                                fromViewController: topMostViewController
                            ) { maybeError, _ in

                                // Maps Error? to Result<(), AdConsentError>
                                let result: Result<(), AdConsentError> =
                                    Optional<SystemError<Int>>.make(maybeError as NSError?)
                                    .maybeToRight(())
                                    .mapError { .other($0) }

                                observer(result)

                            }

                        }
                                            
                    default:
                        return SignalProducer(error: .notUntunneled)
                        
                    }
                    
                }
            
        }
        .mapError { adConsentError in
            .adConsentError(adConsentError)
        }
        .flatMap(.latest) { () -> SignalProducer<GADInitializationStatus, AdSdkInitError> in
            
            tunnelStatusSignal
                .take(first: 1)
                .flatMap(.latest) { vpnStatus in
                    
                    switch vpnStatus {
                    case .invalid, .disconnected:
                        
                        return SignalProducer.async { observer in
                            
                            GADMobileAds.sharedInstance().start { gadInitializationStatus in
                                
                                // If no ad adapters are ready to service ad requests,
                                // SDK initialization is considered to have failed.
                                guard gadInitializationStatus.adaptersReady.count > 0 else {
                                    observer(.failure(.adMobSDKInitNoAdaptersReady(gadInitializationStatus)))
                                    return
                                }
                                
                                // There is at least one adapter ready to service ad requests.
                                observer(.success(gadInitializationStatus))
                                
                            }
                        }
                        
                    default:
                        return .empty
                        
                    }
                    
                }
        }
    
}

fileprivate extension GADInitializationStatus {
    
    /// Returns list of adapters that are ready to service ad requests.
    var adaptersReady: [String: GADAdapterStatus] {
        
        self.adapterStatusesByClassName.filter { (key: String, value: GADAdapterStatus) in
            
            value.state == .ready
            
        }
        
    }
    
}

extension AdState {
    
    /// True if any ad is currently presented.
    var isPresentingAd: Bool {
        
        if case .loadSucceeded(.presenting) = self.interstitialAdControllerStatus {
            return true
        }
        
        if case .loadSucceeded(.presenting) = self.rewardedVideoAdControllerStatus {
            return true
        }
        
        return false
        
    }
    
}
