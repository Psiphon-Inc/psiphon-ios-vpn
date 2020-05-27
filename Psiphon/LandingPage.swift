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

fileprivate let landingPageTag = LogTag("LandingPage")

struct LandingPageReducerState {
    var pendingLandingPageOpening: Bool
    let tunnelConnection: TunnelConnection?
}

enum LandingPageAction {
    case tunnelConnectedAfterIntentSwitchedToStart
    case _urlOpened(success: Bool)
}

typealias LandingPageEnvironment = (
    feedbackLogger: FeedbackLogger,
    sharedDB: PsiphonDataSharedDB,
    urlHandler: URLHandler,
    psiCashEffects: PsiCashEffects,
    psiCashAuthPackageSignal: SignalProducer<PsiCashAuthPackage, Never>
)

func landingPageReducer(
    state: inout LandingPageReducerState, action: LandingPageAction,
    environment: LandingPageEnvironment
) -> [Effect<LandingPageAction>] {
    switch action {
    case .tunnelConnectedAfterIntentSwitchedToStart:
        guard !state.pendingLandingPageOpening else {
            return [
                environment.feedbackLogger.log(
                    .info, tag: landingPageTag, "pending landing page opening").mapNever()
            ]
        }
        guard let tunnelConnection = state.tunnelConnection else {
            environment.feedbackLogger.fatalError("expected a valid tunnel provider")
        }
        
        guard let landingPages = NonEmpty(array: environment.sharedDB.getHomepages()) else {
            return [
                Effect(value: ._urlOpened(success: false)),
                environment.feedbackLogger.log(
                    .warn, tag: landingPageTag, "no landing pages found").mapNever()
            ]
        }
        
        state.pendingLandingPageOpening = true
        
        let randomlySelectedURL = landingPages.randomElement()!.url
        
        return [
            modifyLandingPagePendingEarnerToken(
                url: randomlySelectedURL,
                authPackageSignal: environment.psiCashAuthPackageSignal,
                psiCashEffects: environment.psiCashEffects
            ).flatMap(.latest) {
                environment.urlHandler.open($0, tunnelConnection)
            }
            .map(LandingPageAction._urlOpened(success:))
        ]

    case ._urlOpened(success: _):
        state.pendingLandingPageOpening = false
        return []

    }
}

fileprivate func modifyLandingPagePendingEarnerToken(
    url: URL, authPackageSignal: SignalProducer<PsiCashAuthPackage, Never>,
    psiCashEffects: PsiCashEffects
) -> Effect<URL> {
    authPackageSignal
        .map(\.hasEarnerToken)
        .falseIfNotTrue(within: PsiCashHardCodedValues.getEarnerTokenTimeout)
        .flatMap(.latest) { hasEarnerToken -> SignalProducer<URL, Never> in
            if hasEarnerToken {
                return psiCashEffects.modifyLandingPage(url)
            } else {
                return SignalProducer(value: url)
            }
    }
}
