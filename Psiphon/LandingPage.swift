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

fileprivate let landingPageTag = LogTag("LandingPage")

struct LandingPageReducerState: Equatable {
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
    psiCashAccountTypeSignal: SignalProducer<PsiCashAccountType?, Never>,
    mainDispatcher: MainDispatcher
)

let landingPageReducer = Reducer<LandingPageReducerState
                                 , LandingPageAction
                                 , LandingPageEnvironment> {
    state, action, environment in
    
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
            return []
        }
        
        guard let landingPages = NonEmpty(array: environment.sharedDB.getHomepages()) else {
            return [
                Effect(value: ._urlOpened(success: false)),
                environment.feedbackLogger.log(
                    .warn, tag: landingPageTag, "no landing pages found").mapNever()
            ]
        }
        
        state.pendingLandingPageOpening = true
        
        #if DEV_RELEASE
        // Hard-coded landing page for PsiCash accounts testing
        let randomlySelectedURL = URL(string: "https://landing.dev.psi.cash/dev-index.html")!
        #else
        // let randomlySelectedURL = landingPages.randomElement()!.url
        let randomlySelectedURL = URL(string: "https://landing.psi.cash")!
        #endif
        
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
