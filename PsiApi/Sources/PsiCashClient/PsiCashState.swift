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
import Utilities
import PsiApi

public typealias PendingPsiCashRefresh =
    PendingResult<Utilities.Unit, ErrorEvent<PsiCashRefreshError>>

public struct PsiCashState: Equatable {
    public var purchasing: PsiCashPurchasingState
    public var rewardedVideo: RewardedVideoState
    public var libData: PsiCashLibData
    public var pendingPsiCashRefresh: PendingPsiCashRefresh
    /// True if PsiCashLibData has been loaded from persisted value.
    public var libLoaded: Bool
}

extension PsiCashState {
    
    public init() {
        purchasing = .none
        rewardedVideo = .init()
        libData = .init()
        pendingPsiCashRefresh = .completed(.success(.unit))
        libLoaded = false
    }
    
    public mutating func appDidLaunch(_ libData: PsiCashLibData) {
        self.libData = libData
        self.libLoaded = true
    }
    
    // Returns the first Speed Boost product that has not expired.
    public var activeSpeedBoost: PurchasedExpirableProduct<SpeedBoostProduct>? {
        let activeSpeedBoosts = libData.activePurchases.items
            .compactMap { $0.speedBoost }
            .filter { !$0.transaction.expired }
        return activeSpeedBoosts[maybe: 0]
    }
}

public enum PsiCashPurchasingState: Equatable {
    case none
    case speedBoost(SpeedBoostPurchasable)
    case error(ErrorEvent<PsiCashPurchaseResponseError>)
    
    /// True if purchasing is completed (succeeded or failed)
    public var completed: Bool {
        switch self {
        case .none: return true
        case .error(_): return true
        case .speedBoost(_): return false
        }
    }
}

public enum RewardedVideoPresentation {
      /*! @const AdPresentationWillAppear Ad view controller will appear. This is not a terminal state. */
      case willAppear
      /*! @const AdPresentationDidAppear Ad view controller did appear. This is not a terminal state. */
      case didAppear
      /*! @const AdPresentationWillDisappear Ad view controller will disappear. This is not a terminal state. */
      case willDisappear
      /*! @const AdPresentationDidDisappear Ad view controller did disappear. This <b>can</b> be a terminal state. */
      case didDisappear
      /*! @const AdPresentationDidRewardUser For rewarded video ads only. Emitted once the user has been rewarded.
       * This <b>can</b> be a terminal state. */
      case didRewardUser

      // Ad presentation error states:
      /*! @const AdPresentationErrorInappropriateState The app is not in the appropriate state to present
       * a particular ad. This is a terminal state.*/
      case errorInappropriateState
      /*! @const AdPresentationErrorNoAdsLoaded No ads are loaded. This is a terminal state. */
      case errorNoAdsLoaded
      /*! @const AdPresentationErrorFailedToPlay Ad failed to play or show. This is a terminal state. */
      case errorFailedToPlay
      /*! @const AdPresentationErrorCustomDataNotSet Rewarded video ad custom data not set. This is a terminal state.
       *  This is to be emitted by rewarded video ads that set custom data during presentation.*/
      case errorCustomDataNotSet
}

public enum RewardedVideoLoadStatus {
    case none
    case inProgress
    case done
    case error
}

public typealias RewardedVideoLoad =
    Result<RewardedVideoLoadStatus, ErrorEvent<RewardedVideoAdLoadError>>

public enum RewardedVideoAdLoadError: HashableError {
    case customDataNotPresent
    case noTunneledRewardedVideoAd
    case requestedAdFailedToLoad
    case adSDKError(SystemError)
}

public struct RewardedVideoState: Equatable {
    public var loading: RewardedVideoLoad = .success(.none)
    public var presentation: RewardedVideoPresentation = .didDisappear
    public var dismissed: Bool = false
    public var rewarded: Bool = false

    public var isLoading: Bool {
        switch loading {
        case .success(.inProgress): return true
        default: return false
        }
    }

    public var rewardedAndDismissed: Bool {
        dismissed && rewarded
    }
}

public enum PsiCashPurchaseResponseError: HashableError {
    case tunnelNotConnected
    case parseError(PsiCashParseError)
    // TODO: map Int to PsiCashStatus from PsiCashLib
    case serverError(status: Int, shouldRetry: Bool, error: SystemError?)
}

public enum PsiCashRefreshError: HashableError {
    /// Refresh request is rejected due to tunnel not connected.
    case tunnelNotConnected
    /// Server has returned 500 error response.
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

public struct PsiCashPurchaseResult: Equatable {
    public let purchasable: PsiCashPurchasableType
    public let refreshedLibData: PsiCashLibData
    public let result: Result<PsiCashPurchasedType, ErrorEvent<PsiCashPurchaseResponseError>>
    
    public init (
        purchasable: PsiCashPurchasableType,
        refreshedLibData: PsiCashLibData,
        result: Result<PsiCashPurchasedType, ErrorEvent<PsiCashPurchaseResponseError>>
    ) {
        self.purchasable = purchasable
        self.refreshedLibData = refreshedLibData
        self.result = result
    }
    
}

extension PsiCashPurchaseResult {

    var shouldRetry: Bool {
        guard case let .failure(errorEvent) = self.result else {
            return false
        }
        switch errorEvent.error {
        case .tunnelNotConnected: return false
        case .parseError(_): return false
        case let .serverError(_, retry, _):
            return retry
        }
    }

}

public struct PsiCashBalance: Equatable {

    public enum BalanceIncreaseExpectationReason: String, CaseIterable {
        case watchedRewardedVideo
        case purchasedPsiCash
    }
    
    public var pendingExpectedBalanceIncrease: BalanceIncreaseExpectationReason?
    
    /// Balance with expected reward amount added.
    /// - Note: This value is either equal to `PsiCashLibData.balance`, or higher if there is expected reward amount.
    public var optimisticBalance: PsiCashAmount
    
    /// PsiCash balance as of last PsiCash refresh state.
    public var lastRefreshBalance: PsiCashAmount
    
    public init(pendingExpectedBalanceIncrease: BalanceIncreaseExpectationReason?,
         optimisticBalance: PsiCashAmount,
         lastRefreshBalance: PsiCashAmount) {
        self.pendingExpectedBalanceIncrease = pendingExpectedBalanceIncrease
        self.optimisticBalance = optimisticBalance
        self.lastRefreshBalance = lastRefreshBalance
    }

}

extension PsiCashBalance {
    
    public init() {
        pendingExpectedBalanceIncrease = .none
        optimisticBalance = .zero
        lastRefreshBalance = .zero
    }
    
}

extension PsiCashBalance {
    
    public mutating func waitingForExpectedIncrease(
        withAddedReward addedReward: PsiCashAmount, reason: BalanceIncreaseExpectationReason,
        persisted: PsiCashPersistedValues
    ) {
        pendingExpectedBalanceIncrease = reason
        if addedReward > .zero {
            let totalExpectedReward = persisted.expectedPsiCashReward + addedReward
            persisted.setExpectedPsiCashReward(totalExpectedReward)
            optimisticBalance = lastRefreshBalance + totalExpectedReward
        }
    }
    
    public static func fromStoredExpectedReward(
        libData: PsiCashLibData, persisted: PsiCashPersistedValues
    ) -> Self {
        let adReward = persisted.expectedPsiCashReward
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

    public static func refreshed(
        refreshedData libData: PsiCashLibData, persisted: PsiCashPersistedValues
    ) -> Self {
        persisted.setExpectedPsiCashReward(.zero)
        return .init(pendingExpectedBalanceIncrease: .none,
                     optimisticBalance: libData.balance,
                     lastRefreshBalance: libData.balance)
    }

}

extension PsiCashAuthPackage {
    
    /// true if the user has minimal tokens for the PsiCash features to function.
    public var hasMinimalTokens: Bool {
        hasSpenderToken && hasIndicatorToken
    }
    
}
