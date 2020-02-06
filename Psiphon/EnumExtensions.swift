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
import SwiftActors
import Promises

/// This file contains boilerplate code to extract the `Promise` objects embedded within actor's messages.
/// This file also constians boiler plate to extract associated value with `Message` enums.

// MARK: Application.swift

extension AppAction {

    var objcEffectAction: ObjcEffectAction? {
        get {
            guard case let .objcEffectAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .objcEffectAction = self, let newValue = newValue else { return }
            self = .objcEffectAction(newValue)
        }
    }

    var psiCash: PsiCashAction? {
        get {
            guard case let .psiCash(value) = self else { return nil }
            return value
        }
        set {
            guard case .psiCash = self, let newValue = newValue else { return }
            self = .psiCash(newValue)
        }
    }

}

// MARK: AppRootActor.swift

extension AppRootActor.Action {

    var psiCashAction: PsiCashActor.PublicAction? {
        guard case let .psiCash(value) = self else { return nil }
        return value
    }

    var inAppPurchaseAction: IAPActor.Action? {
        guard case let .inAppPurchase(value) = self else { return nil }
        return value
    }

    var promise: Promise<Any>? {
        switch self {
        case .landingPage(let action): return action.promise
        case .psiCash(let action): return action.promise
        case .inAppPurchase(let action): return action.promise
        case .verifyPsiCashConsumable(let action): return action.promise
        }
    }
}

// MARK: PsiCashActor.swift

extension PsiCashPurchaseResponseError {
    var userDescription: String {
        switch self {
        case .tunnelNotConnected:
            return UserStrings.Psiphon_is_not_connected()
        case .parseError(_):
            return UserStrings.Operation_failed_alert_message()
        case let .serverError(psiCashStatus, _):
            switch psiCashStatus {
            case .insufficientBalance:
                return UserStrings.Insufficient_psiCash_balance()
            default:
                return UserStrings.Operation_failed_alert_message()
            }
        }
    }
}

extension RefreshReason {

    var expectsBalanceIncrease: Bool {
        switch self {
        case .tunnelConnected: return false
        case .appForegrounded: return false
        case .rewardedVideoAd: return true
        case .psiCashIAP: return true
        case .other: return false
        }
    }

}

extension PsiCashActor.Action {
    var refreshState: Promise<Result<(), ErrorEvent<PsiCashRefreshError>>>? {
        guard case let .public(.refreshState(reason: _, promise: value)) = self else {
            return nil
        }
        return value
    }
}

extension PsiCashActor.RequestResult {
    var refreshStateResult: Result<(), ErrorEvent<PsiCashRefreshError>>? {
        guard case let .refreshStateResult(value) = self else {
            return nil
        }
        return value
    }
}

extension PsiCashActor.Action {
    var promise: Promise<Any>? {
        switch self {
        case .public(let action): return action.promise
        case .internal(let action): return action.promise
        }
    }

    static func pull<R>(
        _ f1: @escaping (PsiCashActor.PublicAction) -> R,
        _ f2: @escaping (PsiCashActor.RequestResult) -> R
    ) -> (PsiCashActor.Action) -> R {
        return { action in
            switch action {
            case .public(let value): return f1(value)
            case .internal(let value): return f2(value)
            }
        }
    }
}

extension PsiCashActor.PublicAction {
    var promise: Promise<Any>? {
        switch self {
        case .refreshState(_, let promise): return promise?.eraseToAny()
        case .purchase(_, let promise): return promise.eraseToAny()
        case .modifyLandingPage(_, let promise): return promise.eraseToAny()
        case .rewardedVideoCustomData(let promise): return promise.eraseToAny()
        case .pendingPsiCashIAP: return nil
        case .receivedRewardedVideoReward(_): return nil
        case .userSubscription(_): return nil
        }
    }
}

// MARK: IAPActor.swift

extension PurchasableProduct {
    var appStoreProduct: AppStoreProduct {
        switch self {
        case let .psiCash(product: product, customData: _): return product
        case let .subscription(product: product): return product
        }
    }
}

extension IAPActor.Action {
    var refreshReceipt: Promise<Result<(), SystemErrorEvent>>? {
        guard case let .refreshReceipt(value) = self else {
            return nil
        }
        return value
    }

    var promise: Promise<Any>? {
        switch self {
        case .buyProduct(_, let promise): return promise.eraseToAny()
        case .refreshReceipt(let promise): return promise.eraseToAny()
        case .verifiedConsumableTransaction(let action): return action.promise
        }
    }
}

extension IAPActor.RequestResult {
    var receiptRefreshResult: Result<Void, SystemErrorEvent>? {
        guard case let .receiptRefreshResult(value) = self else {
            return nil
        }
        return value
    }
}

// MARK: SubscriptionActor.swift

extension SubscriptionState {
    var isSubscribed: Bool {
        switch self {
        case .subscribed(_): return true
        case .notSubscribed: return false
        case .unknown: return false
        }
    }
}
