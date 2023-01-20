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
import Utilities
import ReactiveSwift
import PsiApi
import PsiCashClient
import AppStoreIAP

fileprivate let landingPageTag = LogTag("LandingPage")

struct LandingPageReducerState: Equatable {
    var pendingLandingPageOpening: Bool
    let tunnelConnection: TunnelConnection?
    let applicationParameters: ApplicationParameters
    let psiCashState: PsiCashState
    let subscriptionState: SubscriptionState
    let iapState: IAPState
}

enum LandingPageAction {
    
    /// Signal that external landing page can be opened if one is available.
    case tunnelConnectedAfterIntentSwitchedToStart
    
    /// External landing page.
    case _urlOpened(success: Bool)
    
    /// Presents purchase required prompt.
    case presentPurchaseRequiredPrompt
    
}

struct LandingPageEnvironment {
    let feedbackLogger: FeedbackLogger
    let sharedDB: PsiphonDataSharedDB
    let urlHandler: URLHandler
    let psiCashEffects: PsiCashEffects
    let psiCashAccountTypeSignal: SignalProducer<PsiCashAccountType?, Never>
    let dateCompare: DateCompare
    let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    let mainViewStore: (MainViewAction) -> Effect<Never>
    let mainDispatcher: MainDispatcher
}

let landingPageReducer = Reducer<LandingPageReducerState
                                 , LandingPageAction
                                 , LandingPageEnvironment> {
    state, action, environment in
    
    switch action {
    case .tunnelConnectedAfterIntentSwitchedToStart:
        
        #if DEBUG || DEV_RELEASE
        let ignorePurhcaseRequired = UserDefaults.standard.bool(forKey: UserDefaultsIgnorePurchaseRequiredParam)
        guard ignorePurhcaseRequired || !state.applicationParameters.showPurchaseRequiredPurchasePrompt else {
            return [
                environment.feedbackLogger
                    .log(.info, "skipping landing page (ShowPurchaseRequiredPrompt)").mapNever()
            ]
        }
        #else
        guard !state.applicationParameters.showPurchaseRequiredPurchasePrompt else {
            return [
                environment.feedbackLogger
                    .log(.info, "skipping landing page (ShowPurchaseRequiredPrompt)").mapNever()
            ]
        }
        #endif
        
        
        // Guards that user is not in middle of a PsiCash purchase through App Store.
        if let psiCashPurchaseState = state.iapState.purchasing[.psiCash] {
            switch psiCashPurchaseState {
            case .pending(_):
                return []
                
            case .completed(.success(let unfinishedTx)):
                // Pending verification, or verification failed.
                switch unfinishedTx.verificationStatus {
                case .notRequested, .pendingResponse:
                    return []
                    
                case .requestError(_):
                    // Transaction verification failed.
                    // We're going to ignore the failure reason.
                    break
                }
            case .completed(.failure(_)):
                break
            }
        }
        
        // Guards that user is not purchasing Speed Boost.
        guard !(state.psiCashState.speedBoostPurchase.deferred || state.psiCashState.speedBoostPurchase.pending) else {
            return [
                environment.feedbackLogger
                    .log(.info, "skipping landing page (Pending or deferred PsiCash purchase)").mapNever()
            ]
        }
        
        guard !state.pendingLandingPageOpening else {
            return [
                environment.feedbackLogger.log(
                    .info, tag: landingPageTag, "pending landing page opening").mapNever()
            ]
        }
        
        guard let tunnelConnection = state.tunnelConnection else {
            environment.feedbackLogger.fatalError("expected a valid tunnel provider")
            return []
        }
        
        #if DEBUG || DEV_RELEASE
        let randomlySelectedURL = URL(string: "https://landing.dev.psi.cash/dev-index.html")!
        #else
        guard
            let landingPages = NonEmpty(array: environment.sharedDB.getHomepages()),
            let randomlySelectedURL = landingPages.randomElement()?.url
        else {
            return [
                Effect(value: ._urlOpened(success: false)),
                environment.feedbackLogger.log(
                    .warn, tag: landingPageTag, "no landing pages found").mapNever()
            ]
        }
        #endif
        
        state.pendingLandingPageOpening = true
        
        return [
            modifyLandingPagePendingObtainingToken(
                url: randomlySelectedURL,
                psiCashAccountTypeSignal: environment.psiCashAccountTypeSignal,
                psiCashEffects: environment.psiCashEffects
            ).flatMap(.latest) {
                environment.urlHandler.open($0, tunnelConnection, environment.mainDispatcher)
            }
            .map(LandingPageAction._urlOpened(success:))
        ]

    case ._urlOpened(success: _):
        state.pendingLandingPageOpening = false
        return []
        
    case .presentPurchaseRequiredPrompt:
        
        guard state.applicationParameters.showPurchaseRequiredPurchasePrompt else {
            return []
        }
        
        // Purchase required prompt is shown only once for each "VPN session".
        
        let lastHandledVPNSession = environment.sharedDB
            .getContainerPurchaseRequiredHandledEventLatestVPNSessionNumber()
        
        // Updates PsiphonDataSharedDB that this event was handled.
        environment.sharedDB
            .setContainerPurchaseRequiredHandledEventVPNSessionNumber(
                state.applicationParameters.vpnSessionNumber)
        
        if state.applicationParameters.vpnSessionNumber > lastHandledVPNSession {
            
            // Prompt is presented if the user is not (subscribed or speed-boosted)
            // and is connected (or connecting).
            if NEEvent.canPresentPurchaseRequiredPrompt(
                dateCompare: environment.dateCompare,
                psiCashState: state.psiCashState,
                subscriptionStatus: state.subscriptionState.status,
                tunnelConnectedStatus: state.tunnelConnection?.tunneled ?? .notConnected
            ) {
                
                // If VPN is in connecting state, waits for the VPN to connect first.
                return [
                    environment.tunnelStatusSignal
                        .filter {
                            $0 == .connected
                        }
                        .take(first: 1)
                        .then(
                            environment.mainViewStore(.presentPurchaseRequiredPrompt)
                                .mapNever()
                        ),
                    
                    environment.feedbackLogger
                        .log(.info, "Will present purchase required prompt once connected")
                        .mapNever()
                ]
            } else {
                return [
                    environment.feedbackLogger .log(
                        .info, "Purchase required prompt will not presented").mapNever()
                ]
            }
            
        }
        
        return []
        

    }
}

/// Modifies landing page with PsiCash custom data.
/// If no PsiCash tokens are available, waits up to `PsiCashHardCodedValues.getEarnerTokenTimeout`
/// for PsiCash tokens to be obtained.
fileprivate func modifyLandingPagePendingObtainingToken(
    url: URL,
    psiCashAccountTypeSignal: SignalProducer<PsiCashAccountType?, Never>,
    psiCashEffects: PsiCashEffects
) -> Effect<URL> {
    
    psiCashAccountTypeSignal
        .shouldWait(upto: PsiCashHardCodedValues.getEarnerTokenTimeout,
                    otherwiseEmit: .none,
                    shouldWait: { accountType in
            
            guard let accountType = accountType else {
                // PsiCash account information is not avaible. Should wait.
                return true
            }
            
            switch accountType {
            case .noTokens:
                // No PsiCash tokens are available, should wait for first time retrieval
                // of PsiCash tokens.
                return true
                
            case .tracker, .account(loggedIn: false), .account(loggedIn: true):
                // PsiCash tokens have already been retrieved.
                return false
            }
            
        })
        .flatMap(.latest) { accountType -> Effect<URL> in
            
            // Modifies the landing pages URL if user has tracker tokens or is logged in.
            
            switch accountType {
            case .none, .noTokens, .account(loggedIn: false):
                return Effect(value: url)
            case .tracker, .account(loggedIn: true):
                return psiCashEffects.modifyLandingPage(url)
            }
            
        }
    
}
