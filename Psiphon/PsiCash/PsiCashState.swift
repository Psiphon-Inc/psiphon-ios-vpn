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

typealias PendingPsiCashRefresh = PendingResult<Unit, ErrorEvent<PsiCashRefreshError>>

struct PsiCashState: Equatable {
    var purchasing: PsiCashPurchasingState
    var rewardedVideo: RewardedVideoState
    var libData: PsiCashLibData    
    var pendingPsiCashRefresh: PendingPsiCashRefresh
}

extension PsiCashState {
    
    init() {
        purchasing = .none
        rewardedVideo = .init()
        libData = .init()
        pendingPsiCashRefresh = .completed(.success(.unit))
    }
    
    mutating func appDidLaunch(_ libData: PsiCashLibData) {
        self.libData = libData
    }

    var rewardedVideoProduct: PsiCashPurchasableViewModel {
        PsiCashPurchasableViewModel(
            product: .rewardedVideoAd(loading: self.rewardedVideo.isLoading),
            title: PsiCashHardCodedValues.videoAdRewardTitle,
            subtitle: UserStrings.Watch_rewarded_video_and_earn(),
            price: 0.0)
    }
    
    // Returns the first Speed Boost product that has not expired.
    var activeSpeedBoost: PurchasedExpirableProduct<SpeedBoostProduct>? {
        let activeSpeedBoosts = libData.activePurchases.items
            .compactMap { $0.speedBoost }
            .filter { !$0.transaction.expired }
        return activeSpeedBoosts[maybe: 0]
    }
}

enum PsiCashPurchasingState: Equatable {
    case none
    case speedBoost(SpeedBoostPurchasable)
    case error(ErrorEvent<PsiCashPurchaseResponseError>)
    
    /// True if purchasing is completed (succeeded or failed)
    var completed: Bool {
        switch self {
        case .none: return true
        case .error(_): return true
        case .speedBoost(_): return false
        }
    }
}

typealias RewardedVideoPresentation = AdPresentation
typealias RewardedVideoLoad = Result<AdLoadStatus, ErrorEvent<ErrorRepr>>

struct RewardedVideoState: Equatable {
    var loading: RewardedVideoLoad = .success(.none)
    var presentation: RewardedVideoPresentation = .didDisappear
    var dismissed: Bool = false
    var rewarded: Bool = false

    var isLoading: Bool {
        switch loading {
        case .success(.inProgress): return true
        default: return false
        }
    }

    var rewardedAndDismissed: Bool {
        dismissed && rewarded
    }
}

enum PsiCashPurchaseResponseError: HashableError {
    case tunnelNotConnected
    case parseError(PsiCashParseError)
    case serverError(PsiCashStatus, SystemError?)
}

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

enum PsiCashRefreshError: HashableError {
    /// Refresh request is rejected due to tunnel not connected.
    case tunnelNotConnected
    /// Server has returnd 500 error response.
    /// (PsiCash v1.3.1-0-gd1471c1) the request has already been retried internally and any further retry should not be immediate/
    case serverError
    /// Tokens passed in are invalid.
    /// (PsiCash  v1.3.1-0-gd1471c1) Should never happen. The local user ID will be cleared.
    case invalidTokens
    /// Some other error.
    case error(SystemError)
}

/// `PsiCashTransactionMismatchError` represents errors that are due to state mismatch between
/// the client and the PsiCash server, ignoring programmer error.
/// The client should probably sync its state with the server, and it probably shouldn't retry automatically.
/// The user also probably needs to be informed for an error of this type.
enum PsiCashTransactionMismatchError: HashableError {
    /// Insufficient balance to make the transaction.
    case insufficientBalance
    /// Client has out of date purchase price.
    case transactionAmountMismatch
    /// Client has out of date product list.
    case transactionTypeNotFound
    /// There exists a transaction for the purchase class specified.
    case existingTransaction
}

struct PsiCashPurchaseResult: Equatable {
    let purchasable: PsiCashPurchasableType
    let refreshedLibData: PsiCashLibData
    let result: Result<PsiCashPurchasedType, ErrorEvent<PsiCashPurchaseResponseError>>
}

extension PsiCashPurchaseResult {

    var shouldRetry: Bool {
        guard case let .failure(errorEvent) = self.result else {
            return false
        }
        switch errorEvent.error {
        case .tunnelNotConnected: return false
        case .parseError(_): return false
        case let .serverError(psiCashStatus, _):
            switch psiCashStatus {
            case .invalid, .serverError:
                return true
            case .success, .existingTransaction, .insufficientBalance, .transactionAmountMismatch,
                 .transactionTypeNotFound, .invalidTokens:
                return false
            @unknown default:
                return false
            }
        }
    }

}

struct PsiCashBalance: Equatable {
    
    enum BalanceIncreaseExpectationReason: Equatable {
        case watchedRewardedVideo
        case purchasedPsiCash
    }
    
    var pendingExpectedBalanceIncrease: BalanceIncreaseExpectationReason?
    
    /// Balance with expected reward amount added.
    /// - Note: This value is either equal to `PsiCashLibData.balance`, or higher if there is expected reward amount.
    var optimisticBalance: PsiCashAmount
    
    /// PsiCash balance as of last PsiCash refresh state.
    var lastRefreshBalance: PsiCashAmount
}

extension PsiCashBalance {
    init() {
        pendingExpectedBalanceIncrease = .none
        optimisticBalance = .zero
        lastRefreshBalance = .zero
    }
}

extension PsiCashBalance {
    
    mutating func waitingForExpectedIncrease(
        withAddedReward addedReward: PsiCashAmount, reason: BalanceIncreaseExpectationReason,
        userConfigs: UserDefaultsConfig
    ) {
        pendingExpectedBalanceIncrease = reason
        if addedReward > .zero {
            let totalExpectedReward = userConfigs.expectedPsiCashReward + addedReward
            userConfigs.expectedPsiCashReward = totalExpectedReward
            optimisticBalance = lastRefreshBalance + totalExpectedReward
        }
    }
    
    static func fromStoredExpectedReward(
        libData: PsiCashLibData, userConfigs: UserDefaultsConfig
    ) -> Self {
        let adReward = userConfigs.expectedPsiCashReward
        let reason: BalanceIncreaseExpectationReason?
        if adReward.isZero {
            reason = .none
        } else {
            reason = .watchedRewardedVideo
        }
        return .init(pendingExpectedBalanceIncrease: reason,
                     optimisticBalance: libData.balance + adReward,
                     lastRefreshBalance: libData.balance)
    }

    static func refreshed(
        refreshedData libData: PsiCashLibData, userConfigs: UserDefaultsConfig
    ) -> Self {
        userConfigs.expectedPsiCashReward = PsiCashAmount.zero
        return .init(pendingExpectedBalanceIncrease: .none,
                     optimisticBalance: libData.balance,
                     lastRefreshBalance: libData.balance)
    }

}

extension PsiCashAuthPackage {
    
    /// true if the user has minimal tokens for the PsiCash features to function.
    var hasMinimalTokens: Bool {
        hasSpenderToken && hasIndicatorToken
    }
    
}
