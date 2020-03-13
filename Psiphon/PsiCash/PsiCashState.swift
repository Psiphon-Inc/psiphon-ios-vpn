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
    var balanceState: BalanceState
    var pendingPsiCashRefresh: PendingPsiCashRefresh
}

extension PsiCashState {
    
    init() {
        purchasing = .none
        rewardedVideo = .init()
        libData = .init()
        balanceState = .init(pendingExpectedBalanceIncrease: false,
                             balance: .zero())
        pendingPsiCashRefresh = .completed(.success(.unit))
    }
    
    mutating func appDidLaunch(_ libData: PsiCashLibData) {
        self.libData = libData
        self.balanceState = .fromStoredExpectedReward(libData: libData)
    }

    var rewardedVideoProduct: PsiCashPurchasableViewModel {
        PsiCashPurchasableViewModel(
            product: .rewardedVideoAd(loading: self.rewardedVideo.isLoading),
            title: Current.hardCodedValues.psiCash.videoAdRewardTitle,
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
    case psiCashError(ErrorEvent<PsiCashPurchaseResponseError>)
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

struct BalanceState: Equatable {
    /// Indicates an expected increase in PsiCash balance after next sync with the PsiCash server.
    var pendingExpectedBalanceIncrease: Bool
    
    /// Balance with expected rewrad amount added.
    /// - Note: This value is either equal to `PsiCashLibData.balance`, or higher if there is expected reward amount.
    var balance: PsiCashAmount
}

extension BalanceState {
    static func fromStoredExpectedReward(libData: PsiCashLibData) -> Self {
        let reward = Current.userConfigs.expectedPsiCashReward
        return .init(pendingExpectedBalanceIncrease: !reward.isZero,
                     balance: libData.balance + reward)
    }

    static func refreshed(refreshedData libData: PsiCashLibData) -> Self {
        Current.userConfigs.expectedPsiCashReward = PsiCashAmount.zero()
        return .init(pendingExpectedBalanceIncrease: false, balance: libData.balance)
    }

    static func waitingForExpectedIncrease(withAddedReward addedReward: PsiCashAmount,
                                           libData: PsiCashLibData) -> Self {
        let newBalance: PsiCashAmount
        if addedReward > .zero() {
            let newRewardAmount = Current.userConfigs.expectedPsiCashReward + addedReward
            Current.userConfigs.expectedPsiCashReward = newRewardAmount
            newBalance = libData.balance + newRewardAmount
        } else {
            newBalance = libData.balance
        }
        return .init(pendingExpectedBalanceIncrease: true, balance: newBalance)
    }

}
