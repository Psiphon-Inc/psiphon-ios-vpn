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

fileprivate let landingPageTag = LogTag("LandingPage")

typealias RestrictedURL = PredicatedValue<URL, TunnelProviderVPNStatus>

struct LandingPageReducerState<T: TunnelProviderManager> {
    var pendingLandingPageOpening: Bool
    let tunnelProviderManager: WeakRef<T>?
}

enum LandingPageAction {
    case tunnelConnectedAfterIntentSwitchedToStart
    case _urlOpened(success: Bool)
}

typealias LandingPageEnvironment<T: TunnelProviderManager> = (
    sharedDB: PsiphonDataSharedDB,
    urlHandler: URLHandler<T>,
    psiCashEffects: PsiCashEffect,
    psiCashAuthPackageSignal: SignalProducer<PsiCashAuthPackage, Never>
)

func landingPageReducer<T: TunnelProviderManager>(
    state: inout LandingPageReducerState<T>, action: LandingPageAction,
    environment: LandingPageEnvironment<T>
) -> [Effect<LandingPageAction>] {
    switch action {
    case .tunnelConnectedAfterIntentSwitchedToStart:
        guard !state.pendingLandingPageOpening else {
            return [
                feedbackLog(.info, tag: landingPageTag, "pending landing page opening").mapNever()
            ]
        }
        guard let tpmWeakRef = state.tunnelProviderManager else {
            fatalError("expected a valid tunnel provider")
        }
        
        guard let landingPages = NonEmpty(array: environment.sharedDB.getHomepages()) else {
            return [
                Effect(value: ._urlOpened(success: false)),
                feedbackLog(.warn, tag: landingPageTag, "no landing pages found").mapNever()
            ]
        }
        
        state.pendingLandingPageOpening = true
        
        let randomlySelectedURL = RestrictedURL(value: landingPages.randomElement()!.url,
                                                predicate: { $0 == .connected })
        
        return [
            modifyLandingPagePendingEarnerToken(
                url: randomlySelectedURL,
                authPackageSignal: environment.psiCashAuthPackageSignal,
                psiCashEffects: environment.psiCashEffects
            ).flatMap(.latest) {
                environment.urlHandler.open($0, tpmWeakRef)
            }
            .map(LandingPageAction._urlOpened(success:))
        ]

    case ._urlOpened(success: _):
        state.pendingLandingPageOpening = false
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
