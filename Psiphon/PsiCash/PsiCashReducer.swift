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
import PsiApi

enum PsiCashAction {
    case buyPsiCashProduct(PsiCashPurchasableType)
    case psiCashProductPurchaseResult(PsiCashPurchaseResult)
    
    case refreshPsiCashState
    case refreshPsiCashStateResult(PsiCashRefreshResult)
    
    case showRewardedVideoAd
    case rewardedVideoPresentation(RewardedVideoPresentation)
    case rewardedVideoLoad(RewardedVideoLoad)
    case connectToPsiphonTapped
    case dismissedAlert(PsiCashAlertDismissAction)
}

enum PsiCashAlertDismissAction {
    case rewardedVideo
    case speedBoostAlreadyActive
}

struct PsiCashReducerState: Equatable {
    var psiCashBalance: PsiCashBalance
    var psiCash: PsiCashState
    let subscription: SubscriptionState
    let tunnelConnection: TunnelConnection?
}

typealias PsiCashEnvironment = (
    feedbackLogger: FeedbackLogger,
    psiCashEffects: PsiCashEffect,
    sharedDB: PsiphonDataSharedDB,
    userConfigs: UserDefaultsConfig,
    notifier: Notifier,
    vpnActionStore: (VPNPublicAction) -> Effect<Never>,
    // TODO: Remove this dependency from reducer's environment. UI-related effects
    // unnecessarily complicate reducers.
    objcBridgeDelegate: ObjCBridgeDelegate?,
    rewardedVideoAdBridgeDelegate: RewardedVideoAdBridgeDelegate
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
        }
        state.psiCash.purchasing = .speedBoost(purchasable)
        return [
            environment.psiCashEffects.purchaseProduct(purchasableType,
                                                       tunnelConnection: tunnelConnection)
                .map(PsiCashAction.psiCashProductPurchaseResult)
        ]
        
    case .psiCashProductPurchaseResult(let purchaseResult):
        guard case .speedBoost(_) = state.psiCash.purchasing else {
            environment.feedbackLogger.fatalError("""
                Expected '.speedBoost' state:'\(String(describing: state.psiCash.purchasing))'
                """)
        }
        guard purchaseResult.purchasable.speedBoost != nil else {
            environment.feedbackLogger.fatalError("""
                Expected '.speedBoost'; purchasable: '\(purchaseResult.purchasable)'
                """)
        }
        
        state.psiCash.libData = purchaseResult.refreshedLibData
        state.psiCashBalance = .refreshed(refreshedData: purchaseResult.refreshedLibData,
                                          userConfigs: environment.userConfigs)
        switch purchaseResult.result {
        case .success(let purchasedType):
            guard case .speedBoost(let purchasedProduct) = purchasedType else {
                environment.feedbackLogger.fatalError("Expected '.speedBoost' purchased type")
            }
            state.psiCash.purchasing = .none
            return [
                .fireAndForget {
                    environment.sharedDB.appendNonSubscriptionEncodedAuthorization(
                        purchasedProduct.transaction.authorization.rawData
                    )
                    environment.notifier.post(NotifierUpdatedNonSubscriptionAuths)
                },
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
        return [
            environment.psiCashEffects
                .refreshState(andGetPricesFor: PsiCashTransactionClass.allCases,
                              tunnelConnection: tunnelConnection)
                .map(PsiCashAction.refreshPsiCashStateResult)
        ]
        
    case .refreshPsiCashStateResult(let result):
        state.psiCash.pendingPsiCashRefresh = result.map { $0.map { _ in .unit } }
        if case .completed(.success(let refreshedLibData)) = result {
            state.psiCash.libData = refreshedLibData
            state.psiCashBalance = .refreshed(refreshedData: refreshedLibData,
                                              userConfigs: environment.userConfigs)
        }
        return []
        
    case .showRewardedVideoAd:
        guard case .notSubscribed = state.subscription.status else {
            return []
        }
        
        switch state.tunnelConnection?.tunneled {
        case .connected:
            state.psiCash.rewardedVideo.combine(
                loading: .failure(ErrorEvent(.noTunneledRewardedVideoAd))
            )
            return []
        case .connecting, .disconnecting:
            return []
        case .notConnected, .none:
            guard let customData = environment.psiCashEffects.rewardedVideoCustomData() else {
                state.psiCash.rewardedVideo.combine(
                    loading: .failure(ErrorEvent(.customDataNotPresent)))
                return []
            }
            return [
                .fireAndForget {
                    environment.objcBridgeDelegate?.presentUntunneledRewardedVideoAd(
                        customData: customData,
                        delegate: environment.rewardedVideoAdBridgeDelegate)
                }
            ]
        }
        
    case .rewardedVideoPresentation(let presentation):
        state.psiCash.rewardedVideo.combine(presentation: presentation)
        
        if state.psiCash.rewardedVideo.rewardedAndDismissed {
            let rewardAmount = PsiCashHardCodedValues.videoAdRewardAmount
            state.psiCashBalance.waitingForExpectedIncrease(withAddedReward: rewardAmount,
                                                            reason: .watchedRewardedVideo,
                                                            userConfigs: environment.userConfigs)
            return [Effect { .refreshPsiCashState }]
        } else {
            return []
        }
        
    case .rewardedVideoLoad(let loadStatus):
        state.psiCash.rewardedVideo.combine(loading: loadStatus)
        return []
        
    case .dismissedAlert(let dismissed):
        switch dismissed {
        case .speedBoostAlreadyActive:
            state.psiCash.purchasing = .none
            return []
        case .rewardedVideo:
            state.psiCash.rewardedVideo.combineWithErrorDismissed()
            return []
        }
        
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
