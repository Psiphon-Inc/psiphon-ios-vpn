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

public struct PsiCashState: Equatable {
    
    // Failure type matches PsiCashEffects.PsiCashRefreshResult.Failure
    public typealias PendingRefresh =
        PendingResult<Utilities.Unit,
                      ErrorEvent<TunneledPsiCashRequestError<
                                    PsiCashRequestError<PsiCashRefreshErrorStatus>>>>
    
    /// Represents whether PsiCash accounts is pending login or logout.
    public enum LoginLogoutPendingValue: Equatable {
        /// PsiCash accounts pending login.
        case login
        /// PsiCash accounts pending logout.
        case logout
    }
    
    public typealias PendingAccountLoginLogoutEvent =
        Event<PendingValue<LoginLogoutPendingValue,
                           Either<PsiCashEffects.PsiCashAccountLoginResult,
                                  PsiCashEffects.PsiCashAccountLogoutResult>>>?
    
    public var purchasing: PsiCashPurchasingState
    public var rewardedVideo: RewardedVideoState
    public var libData: PsiCashLibData
    
    public var pendingAccountLoginLogout: PendingAccountLoginLogoutEvent
    public var pendingPsiCashRefresh: PendingRefresh
    /// True if PsiCashLibData has been loaded from persisted value.
    public var libLoaded: Bool
}

extension PsiCashState {
    
    public init() {
        purchasing = .none
        rewardedVideo = .init()
        libData = .init()
        pendingAccountLoginLogout = nil
        pendingPsiCashRefresh = .completed(.success(.unit))
        libLoaded = false
    }
    
    public mutating func initialized(_ libData: PsiCashLibData) {
        self.libData = libData
        self.libLoaded = true
    }
    
    /// Returns the first Speed Boost product that has not expired.
    public func activeSpeedBoost(
        _ dateCompare: DateCompare
    ) -> PurchasedExpirableProduct<SpeedBoostProduct>? {
        
        let activeSpeedBoosts = libData.activePurchases.toPairs().successes
            .compactMap(\.speedBoost)
            .filter { !$0.transaction.isExpired(dateCompare) }
        
        return activeSpeedBoosts[maybe: 0]
    }
}

public enum PsiCashPurchasingState: Equatable {
    case none
    case speedBoost(SpeedBoostPurchasable)
    case error(PsiCashEffects.PsiCashNewExpiringPurchaseResult.Error)
    
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

public enum PsiCashRequestError<ErrorStatus>: HashableError where
    ErrorStatus: PsiCashErrorStatusProtocol {
    
    /// Request was submitted successfully, but returned an error status.
    case errorStatus(ErrorStatus)
    
    /// Sending the request failed utterly.
    case requestFailed(PsiCashLibError)
}

/// Represents a PsiCash client library produced request error, along with the an additional
/// `.tunnelNotConnected` error case.
public enum TunneledPsiCashRequestError<RequestError: HashableError>: HashableError {
    /// Request was not sent since tunnel was not connected.
    case tunnelNotConnected
    
    case requestError(RequestError)
}

/// Represents error values of a PsiCash library refresh action.
/// Errors generated by the app are not represented here e.g. a tunnel not connected error.
public typealias PsiCashRefreshError = PsiCashRequestError<PsiCashRefreshErrorStatus>

/// Represents error values of a PsiCash library new expiring purchase action.
/// Errors generated by the app are not represented here e.g. a tunnel not connected error.
public typealias PsiCashNewExpiringPurchaseError =
    PsiCashRequestError<PsiCashNewExpiringPurchaseErrorStatus>

/// Represents error values of a PsiCash library account login action.
/// Errors generated by the app are not represented here e.g. a tunnel not connected error.
public typealias PsiCashAccountLoginError =
    PsiCashRequestError<PsiCashAccountLoginErrorStatus>


public struct PsiCashBalance: Equatable {

    public enum BalanceIncreaseExpectationReason: String, CaseIterable {
        case watchedRewardedVideo
        case purchasedPsiCash
    }
    
    public private(set) var pendingExpectedBalanceIncrease: BalanceIncreaseExpectationReason?
    
    /// Balance with expected reward amount added.
    /// - Note: This value is either equal to `PsiCashLibData.balance`, or higher if there is expected reward amount.
    public private(set) var optimisticBalance: PsiCashAmount
    
    /// PsiCash balance as of last PsiCash refresh state.
    public private(set) var lastRefreshBalance: PsiCashAmount
    
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
