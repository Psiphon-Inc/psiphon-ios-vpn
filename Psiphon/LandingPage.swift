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
import ReactiveSwift

typealias RestrictedURL = PredicatedValue<URL, NEVPNStatus>

enum LandingPageShownState {
    case pending
    case shown
    case notShown
    case notShownDueSpeedBoostPurchase
}

struct LandingPageReducerState {
    var shownLandingPage: LandingPageShownState
    let activeSpeedBoost: PurchasedExpirableProduct<SpeedBoostProduct>?
}

enum LandingPageAction {
    /// Will try to open a randomly selected landing page from stored landing pages if VPN is connected.
    case openRandomlySelectedLandingPage
    case urlOpened(success: Bool)
    /// Resets the shown landing page for current session flag.
    case reset
}

typealias LandingPageEnvironment = (
    sharedDB: PsiphonDataSharedDB,
    urlHandler: URLHandler,
    psiCashEffects: PsiCashEffect,
    vpnManager: VPNManager,
    vpnStatusSignal: SignalProducer<NEVPNStatus, Never>,
    psiCashAuthPackageSignal: SignalProducer<PsiCashAuthPackage, Never>
)

func landingPageReducer(
    state: inout LandingPageReducerState, action: LandingPageAction,
    environment: LandingPageEnvironment
) -> [Effect<LandingPageAction>] {
    switch action {
    case .openRandomlySelectedLandingPage:
        switch (state.shownLandingPage, state.activeSpeedBoost) {
        case (.pending, _),
             (.shown, _):
            return []
            
        case (.notShown, .some(_)):
            state.shownLandingPage = .notShownDueSpeedBoostPurchase
            return []
            
        case (.notShown, .none),
             (.notShownDueSpeedBoostPurchase, _):
            
            state.shownLandingPage = .pending
            return [
                // Waits up to 1 second for vpnStatus to change to `.connected`.
                environment.vpnStatusSignal
                    .map { $0 == .connected }
                    .falseIfNotTrue(within: .seconds(1))
                    .take(first: 1)
                    .flatMap(.latest) { connected -> SignalProducer<LandingPageAction, Never> in
                        if connected {
                            guard
                                let landingPages = environment.sharedDB.getHomepages(),
                                landingPages.count > 1 else {
                                return Effect(value: .urlOpened(success: false))
                            }
                            
                            let randomlySelectedURL =
                                RestrictedURL(value: landingPages.randomElement()!.url,
                                              predicate: { $0 == .connected })
                            
                            return modifyLandingPagePendingEarnerToken(
                                url: randomlySelectedURL,
                                authPackageSignal: environment.psiCashAuthPackageSignal,
                                psiCashEffects: environment.psiCashEffects
                            ).flatMap(.latest) {
                                environment.urlHandler.open($0, environment.vpnManager)
                            }
                            .map(LandingPageAction.urlOpened(success:))
                        } else {
                            return Effect(value: .urlOpened(success: false))
                        }
                }
            ]
        }
        
    case .urlOpened(success: let success):
        if success {
            state.shownLandingPage = .shown
        } else {
            state.shownLandingPage = .notShown
        }
        return []
        
    case .reset:
        state.shownLandingPage =  .notShown
        return []
    }
}

fileprivate func modifyLandingPagePendingEarnerToken(
    url: RestrictedURL, authPackageSignal: SignalProducer<PsiCashAuthPackage, Never>,
    psiCashEffects: PsiCashEffect
) -> Effect<RestrictedURL> {
    authPackageSignal
        .map(\.hasEarnerToken)
        .falseIfNotTrue(within: PsiCashHardCodedValues.getEarnerTokenTimeout)
        .flatMap(.latest) { hasEarnerToken -> SignalProducer<RestrictedURL, Never> in
            if hasEarnerToken {
                return psiCashEffects.modifyLandingPage(url)
            } else {
                return SignalProducer(value: url)
            }
    }
}
