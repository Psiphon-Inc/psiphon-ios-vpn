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
}

typealias PsiCashEnvironment = (
    psiCashEffects: PsiCashEffect,
    sharedDB: PsiphonDataSharedDB,
    userConfigs: UserDefaultsConfig,
    notifier: Notifier,
    vpnManager: VPNManager,
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
        guard case .notSubscribed = state.subscription.status else {
            return []
        }
        guard state.psiCash.purchasing.completed else {
            return []
        }
        guard let purchasable = purchasableType.speedBoost else {
            fatalError()
        }
        state.psiCash.purchasing = .speedBoost(purchasable)
        return [
            environment.psiCashEffects.purchaseProduct(purchasableType,
                                                       vpnManager: environment.vpnManager)
                .map(PsiCashAction.psiCashProductPurchaseResult)
        ]
        
    case .psiCashProductPurchaseResult(let purchaseResult):
        guard case .speedBoost(_) = state.psiCash.purchasing else {
            fatalError("""
                Expected '.speedBoost' state:'\(String(describing: state.psiCash.purchasing))'
                """)
        }
        guard purchaseResult.purchasable.speedBoost != nil else {
            fatalError("Expected '.speedBoost'; purchasable: '\(purchaseResult.purchasable)'")
        }
        
        state.psiCash.libData = purchaseResult.refreshedLibData
        state.psiCashBalance = .refreshed(refreshedData: purchaseResult.refreshedLibData,
                                          userConfigs: environment.userConfigs)
        switch purchaseResult.result {
        case .success(let purchasedType):
            guard case .speedBoost(let purchasedProduct) = purchasedType else {
                fatalError("Expected '.speedBoost' purchased type")
            }
            state.psiCash.purchasing = .none
            return [
                .fireAndForget {
                    environment.sharedDB.appendNonSubscriptionAuthorization(
                        purchasedProduct.transaction.authorization
                    )
                    environment.notifier.post(NotifierUpdatedNonSubscriptionAuths)
                },
                .fireAndForget {
                    environment.objcBridgeDelegate?.dismiss(screen: .psiCash)
                }
            ]
            
        case .failure(let errorEvent):
            state.psiCash.purchasing = .error(errorEvent)
            return [
                .fireAndForget {
                    PsiFeedbackLogger.error(withType: "PsiCash",
                                            message: "psicash product purchase failed",
                                            object: errorEvent)
                }
            ]
        }
        
    case .refreshPsiCashState:
        guard case .notSubscribed = state.subscription.status else {
            return []
        }
        guard case .completed(_) = state.psiCash.pendingPsiCashRefresh else {
            return []
        }
        return [
            environment.psiCashEffects
                .refreshState(andGetPricesFor: PsiCashTransactionClass.allCases,
                              vpnManager: environment.vpnManager)
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
        // TODO: Provide a more informative error message
        guard let customData = environment.psiCashEffects.rewardedVideoCustomData() else {
            state.psiCash.rewardedVideo.combine(loading:
                .failure(ErrorEvent(ErrorRepr(repr: "PsiCash data missing"))))
            return []
        }
        return [
            .fireAndForget {
                environment.objcBridgeDelegate?.presentRewardedVideoAd(
                    customData: customData,
                    delegate: environment.rewardedVideoAdBridgeDelegate)
            }
        ]
        
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
            .fireAndForget {
                environment.vpnManager.startTunnel()
            },
            .fireAndForget {
                environment.objcBridgeDelegate?.dismiss(screen: .psiCash)
            }
        ]
    }
}
