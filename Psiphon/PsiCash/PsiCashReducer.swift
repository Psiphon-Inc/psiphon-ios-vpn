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
import AppStoreIAP
import PsiApi
import PsiCashClient

struct PsiCashReducerState: Equatable {
    var psiCashBalance: PsiCashBalance
    var psiCash: PsiCashState
    let subscription: SubscriptionState
    let tunnelConnection: TunnelConnection?
}

typealias PsiCashEnvironment = (
    platform: Platform,
    feedbackLogger: FeedbackLogger,
    psiCashEffects: PsiCashEffects,
    sharedDB: PsiphonDataSharedDB,
    psiCashPersistedValues: PsiCashPersistedValues,
    notifier: PsiApi.Notifier,
    vpnActionStore: (VPNPublicAction) -> Effect<Never>,
    // TODO: Remove this dependency from reducer's environment. UI-related effects
    // unnecessarily complicate reducers.
    objcBridgeDelegate: ObjCBridgeDelegate?
)

func psiCashReducer(
    state: inout PsiCashReducerState, action: PsiCashAction, environment: PsiCashEnvironment
) -> [Effect<PsiCashAction>] {
    switch action {
    case .buyPsiCashProduct(let purchasableType):
        guard let tunnelConnection = state.tunnelConnection else {
            return []
        }
        guard case .notSubscribed = state.subscription.status else {
            return []
        }
        guard state.psiCash.purchasing.completed else {
            return []
        }
        guard let purchasable = purchasableType.speedBoost else {
            environment.feedbackLogger.fatalError(
                "Expected a PsiCashPurchasable in '\(purchasableType)'")
            return []
        }
        state.psiCash.purchasing = .speedBoost(purchasable)
        return [
            environment.psiCashEffects.purchaseProduct(purchasableType, tunnelConnection)
                .map(PsiCashAction.psiCashProductPurchaseResult)
        ]
        
    case .psiCashProductPurchaseResult(let purchaseResult):
        guard case .speedBoost(_) = state.psiCash.purchasing else {
            environment.feedbackLogger.fatalError("""
                Expected '.speedBoost' state:'\(String(describing: state.psiCash.purchasing))'
                """)
            return []
        }
        guard purchaseResult.purchasable.speedBoost != nil else {
            environment.feedbackLogger.fatalError("""
                Expected '.speedBoost'; purchasable: '\(purchaseResult.purchasable)'
                """)
            return []
        }
        
        state.psiCash.libData = purchaseResult.refreshedLibData
        state.psiCashBalance = .refreshed(refreshedData: purchaseResult.refreshedLibData,
                                          persisted: environment.psiCashPersistedValues)
        switch purchaseResult.result {
        case .success(let purchasedType):
            guard case .speedBoost(let purchasedProduct) = purchasedType else {
                environment.feedbackLogger.fatalError("Expected '.speedBoost' purchased type")
                return []
            }
            state.psiCash.purchasing = .none
            return [
                
                environment.feedbackLogger.log(
                    .info, "Speed Boost purchased successfully: '\(purchasedProduct)'").mapNever(),
                
                // Updates sharedDB with new auths, and notifies
                // network extension of the change if required.
                setSharedDBPsiCashAuthTokens(
                    state.psiCash.libData,
                    sharedDB: environment.sharedDB,
                    notifier: environment.notifier
                ).mapNever(),
                
                .fireAndForget {
                    environment.objcBridgeDelegate?.dismiss(screen: .psiCash, completion: nil)
                }
                
            ]
            
        case .failure(let errorEvent):
            state.psiCash.purchasing = .error(errorEvent)
            return [ environment.feedbackLogger.log(.error, errorEvent).mapNever() ]
        }
        
    case .refreshPsiCashState:
        guard let tunnelConnection = state.tunnelConnection else {
            return []
        }
        guard case .notSubscribed = state.subscription.status else {
            return []
        }
        guard case .completed(_) = state.psiCash.pendingPsiCashRefresh else {
            return []
        }
        
        state.psiCash.pendingPsiCashRefresh = .pending
        
        return [
            environment.feedbackLogger.log(.info, "PsiCash: refresh state started").mapNever(),
            environment.psiCashEffects
                .refreshState(PsiCashTransactionClass.allCases, tunnelConnection)
                .map(PsiCashAction.refreshPsiCashStateResult)
        ]
        
    case .refreshPsiCashStateResult(let result):
        state.psiCash.pendingPsiCashRefresh = result.map { $0.map { _ in .unit } }

        switch result {
        case .completed(.success(let refreshedLibData)):
            state.psiCash.libData = refreshedLibData
            state.psiCashBalance = .refreshed(refreshedData: refreshedLibData,
                                              persisted: environment.psiCashPersistedValues)
            return [
                
                // Updates sharedDB with new auths, and notifies
                // network extension if required.
                setSharedDBPsiCashAuthTokens(
                    state.psiCash.libData,
                    sharedDB: environment.sharedDB,
                    notifier: environment.notifier
                ).mapNever(),
                
                environment.feedbackLogger.log(.info, "PsiCash: refresh state success").mapNever()
            ]
        case .completed(.failure(let error)):
            return [
                environment.feedbackLogger.log(
                    .warn,
                    LogMessage(stringLiteral:"PsiCash: refresh state error: " + String(describing: error))
                ).mapNever()
            ]
        case .pending:
            return []
        }
        
    case .dismissedAlert(let dismissed):
        switch dismissed {
        case .speedBoostAlreadyActive:
            state.psiCash.purchasing = .none
            return []
        }
        
    case let .userDidEarnReward(rewardAmount, reason):
        
        // Increases displayed PsiCash balance optimistically
        // with the given rewardAmount, until PsiCash state is refreshed.
        
        state.psiCashBalance.waitingForExpectedIncrease(
            withAddedReward: rewardAmount,
            reason: reason,
            persisted: environment.psiCashPersistedValues)
        
        return [ Effect(value: .refreshPsiCashState) ]
        
    case .connectToPsiphonTapped:
        return [
            .fireAndForget { [unowned objcBridgeDelegate = environment.objcBridgeDelegate] in
                objcBridgeDelegate?.dismiss(screen: .psiCash, completion: {
                    objcBridgeDelegate?.startStopVPNWithInterstitial()
                })
            }
        ]
    }
}

/// Sets PsiphonDataSharedDB non-subscription auth tokens,
/// to the active tokens provided by the PsiCash library.
/// If set of active authorizations has changed, then sends a message to the network extension
/// to notify it of the new authorization tokens.
fileprivate func setSharedDBPsiCashAuthTokens(
    _ libData: PsiCashLibData,
    sharedDB: PsiphonDataSharedDB,
    notifier: PsiApi.Notifier
) -> Effect<Never> {

    // Set of all authorizations from PsiCash library.
    let psiCashLibAuths = Set(libData.activePurchases.items.map { parsedPurchase -> String in

        switch parsedPurchase {
        case .speedBoost(let product):
            return product.transaction.authorization.rawData
        }

    })

    return .fireAndForget {

        // Updates PsiphonDataSharedDB with with the set of PsiCash authorizations.
        
        // If current set of authorizations stored by PsiCash library is not equal to
        // the set of non-subscription authorizations stored by the extension
        // sends a notification to the extension of the change.
        let sendNotification = sharedDB.getNonSubscriptionEncodedAuthorizations() != psiCashLibAuths
        
        // Updates set of non-susbscription authorizations stored by the extension.
        sharedDB.setNonSubscriptionEncodedAuthorizations(psiCashLibAuths)

        if sendNotification {
            // Notifies network extension of updated non-subscriptions authorizations.
            notifier.post(NotifierUpdatedNonSubscriptionAuths)
        }

    }

}
