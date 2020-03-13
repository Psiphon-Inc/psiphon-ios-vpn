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

typealias RestrictedURL = PredicatedValue<URL, Environment>

struct LandingPageReducerState {
    var shownLandingPage: Pending<Bool>
    let activeSpeedBoost: PurchasedExpirableProduct<SpeedBoostProduct>?
}

enum LandingPageAction {
    /// Will try to open latest stored landing page for the current session if VPN is connected.
    case open(RestrictedURL)
    
    case urlOpened(success: Bool)
    /// Resets the shown landing page for current session flag.
    case reset
}

func landingPageReducer(
    state: inout LandingPageReducerState, action: LandingPageAction
) -> [Effect<LandingPageAction>] {
    switch action {
    case .open(let url):
        guard case .completed(_) = state.shownLandingPage else {
            return []
        }
        // Landing page not showing if SpeedBoost is active.
        guard case .none = state.activeSpeedBoost else {
            return []
        }
        state.shownLandingPage =  .pending
        return [
            Current.vpnStatus.signalProducer
                .map { $0 == .connected }
                .falseIfNotTrue(within: .seconds(1))
                .take(first: 1)
                .flatMap(.latest) { connected -> SignalProducer<LandingPageAction, Never> in
                    if connected {
                        return modifyLandingPagePendingEarnerToken(url: url)
                            .flatMap(.latest) {
                                Current.urlHandler.open($0)
                        }.map(LandingPageAction.urlOpened(success:))
                    } else {
                        return SignalProducer(value: .urlOpened(success: false))
                    }
            }
        ]
        
    case .urlOpened(success: let success):
        state.shownLandingPage =  .completed(success)
        return []
        
    case .reset:
        state.shownLandingPage =  .completed(false)
        return []
    }
}

fileprivate func modifyLandingPagePendingEarnerToken(url: RestrictedURL) -> Effect<RestrictedURL> {
    Current.app.store.$value.signalProducer
        .map(\.psiCash.libData.authPackage.hasEarnerToken)
        .falseIfNotTrue(within:Current.hardCodedValues.psiCash.getEarnerTokenTimeout)
        .flatMap(.latest) { hasEarnerToken -> SignalProducer<RestrictedURL, Never> in
            if hasEarnerToken {
                return Current.psiCashEffect.modifyLandingPage(url)
            } else {
                return SignalProducer(value: url)
            }
    }
}
