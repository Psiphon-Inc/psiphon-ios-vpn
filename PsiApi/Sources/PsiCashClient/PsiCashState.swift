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
    
    public typealias PsiCashLibState = Result<PsiCashLibData, ErrorRepr>?
    
    // Failure type matches PsiCashEffects.PsiCashRefreshResult.Failure
    public typealias PendingRefresh =
        PendingResult<Utilities.Unit,
                      ErrorEvent<PsiCashRequestError<PsiCashRefreshErrorStatus>>>
    
    /// Represents whether PsiCash accounts is pending login or logout.
    public enum LoginLogoutPendingValue: Equatable {
        /// PsiCash accounts pending login.
        case login
        /// PsiCash accounts pending logout.
        case logout
    }
    
    /// Represents  result of account login/logout.
    public typealias AccountLoginLogoutCompleted =
        Either<PsiCashEffectsProtocol.PsiCashAccountLoginResult,
               PsiCashEffectsProtocol.PsiCashAccountLogoutResult>
    
    /// Represents event of logging in or logging out of PsiCash account.
    public typealias PendingAccountLoginLogoutEvent =
        Event<PendingValue<LoginLogoutPendingValue, AccountLoginLogoutCompleted>>
    
    public var speedBoostPurchase: PsiCashPurchaseState
    
    /// Representation of PsiCash data held by PsiCash library.
    /// If `nil`, PsiCash library is not initialized yet.
    public var libData: PsiCashLibState
    
    public var pendingAccountLoginLogout: PendingAccountLoginLogoutEvent?
    public var pendingPsiCashRefresh: PendingRefresh
    
    
    public init(
        speedBoostPurchase: PsiCashPurchaseState,
        libData: Result<PsiCashLibData, ErrorRepr>? = nil,
        pendingAccountLoginLogout: PsiCashState.PendingAccountLoginLogoutEvent? = nil,
        pendingPsiCashRefresh: PsiCashState.PendingRefresh
    ) {
        self.speedBoostPurchase = speedBoostPurchase
        self.libData = libData
        self.pendingAccountLoginLogout = pendingAccountLoginLogout
        self.pendingPsiCashRefresh = pendingPsiCashRefresh
    }
    
}

extension PsiCashState {
    
    /// Has value if pending PsiCash Accounts login or logout, otherwise `.none`.
    public var isLoggingInOrOut: LoginLogoutPendingValue? {
        
        switch pendingAccountLoginLogout {
        case .none:
            return .none
        case .some(let event):
            switch event.wrapped {
            case .pending(.login):
                return .login
            case .pending(.logout):
                return .logout
            case .completed(_):
                return .none
            }
        }
        
    }
    
}

extension PsiCashState: CustomFieldFeedbackDescription {
    public var feedbackFields: [String : CustomStringConvertible] {
        [
            "purchasing": String(describing: speedBoostPurchase),
            "pendingAccountLoginLogout": String(describing: pendingAccountLoginLogout),
            "pendingPsiCashRefresh": String(describing: pendingPsiCashRefresh)
        ]
    }
}

extension PsiCashState {
    
    public init() {
        speedBoostPurchase = .none
        libData = nil
        pendingAccountLoginLogout = nil
        pendingPsiCashRefresh = .completed(.success(.unit))
    }
    
    /// Returns the first Speed Boost product that has not expired.
    public func activeSpeedBoost(
        _ dateCompare: DateCompare
    ) -> PurchasedExpirableProduct<SpeedBoostProduct>? {
        
        let activeSpeedBoosts = libData?.successToOptional()?.activePurchases.partitionResults().successes
            .compactMap(\.speedBoost)
            .filter { !$0.transaction.isExpired(dateCompare) }
        
        return activeSpeedBoosts?[maybe: 0]
    }
}

/// Represents the purchase state of a PsiCash product e.g. Speed Boost.
public enum PsiCashPurchaseState: Equatable {
    
    /// No product is being purchased.
    case none
    
    /// Purchase is deferred until the tunnel is connected.
    case deferred(PsiCashPurchasableType)
    
    /// Purchase request is made (or imminent), awaiting result.
    case pending(PsiCashPurchasableType)
    
    /// Purchase ended in an error state.
    case error(NewExpiringPurchaseResult.ErrorType)
    
    /// `true` if PsiCash product purchase request is made (or imminenet).
    public var pending: Bool {
        guard case .pending(_) = self else {
            return false
        }
        return true
    }
    
    /// `true` if there is a pending PsiCash product purchase after tunnel is connected.
    public var deferred: Bool {
        guard case .deferred(_) = self else {
            return false
        }
        return true
    }
}

public enum RewardedVideoLoadStatus {
    case none
    case inProgress
    case done
    case error
}

public enum PsiCashRequestError<ErrorStatus>: HashableError where
    ErrorStatus: PsiCashErrorStatusProtocol {
    
    /// Request was submitted successfully, but returned an error status.
    case errorStatus(ErrorStatus)
    
    /// Sending the request failed utterly.
    case requestCatastrophicFailure(PsiCashLibError)

}

/// Represents a PsiCash client library produced request error, along with the an additional
/// `.tunnelNotConnected` error case.
public enum TunneledPsiCashRequestError<RequestError: HashableError>: HashableError {
    /// Request was not sent since tunnel was not connected.
    case tunnelNotConnected
    /// Wrapped RequestError.
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

    public enum BalanceOutOfDateReason: String, CaseIterable {
        case watchedRewardedVideo
        case purchasedPsiCash
        /// Represents a state where PsiCash balance might be incorrect due to PsiCash internal data store migration.
        case psiCashDataStoreMigration
        case otherBalanceUpdateError
    }
    
    public private(set) var balanceOutOfDateReason: BalanceOutOfDateReason?
    
    /// Balance with expected reward amount added.
    /// - Note: This value is either equal to `PsiCashLibData.balance`, or higher if there is expected reward amount.
    public private(set) var optimisticBalance: PsiCashAmount
    
    /// PsiCash balance as of last PsiCash refresh state.
    public private(set) var lastRefreshBalance: PsiCashAmount
    
    public init(balanceOutOfDateReason: BalanceOutOfDateReason?,
         optimisticBalance: PsiCashAmount,
         lastRefreshBalance: PsiCashAmount) {
        self.balanceOutOfDateReason = balanceOutOfDateReason
        self.optimisticBalance = optimisticBalance
        self.lastRefreshBalance = lastRefreshBalance
    }

}

extension PsiCashBalance {
    
    public init() {
        balanceOutOfDateReason = .none
        optimisticBalance = .zero
        lastRefreshBalance = .zero
    }
    
}

extension PsiCashBalance {
    
    public mutating func waitingForExpectedIncrease(
        withAddedReward addedReward: PsiCashAmount,
        reason: BalanceOutOfDateReason,
        persisted: PsiCashPersistedValues
    ) {
        self.balanceOutOfDateReason = reason
        if addedReward > .zero {
            let totalExpectedReward = persisted.expectedPsiCashReward + addedReward
            persisted.setExpectedPsiCashReward(totalExpectedReward)
            self.optimisticBalance = self.lastRefreshBalance + totalExpectedReward
        }
    }
    
    public mutating func balanceOutOfDate(reason: BalanceOutOfDateReason) {
        self.balanceOutOfDateReason = reason
    }
    
    public static func fromStoredExpectedReward(
        libData: PsiCashLibData, persisted: PsiCashPersistedValues
    ) -> Self {
        let adReward = persisted.expectedPsiCashReward
        let reason: BalanceOutOfDateReason?
        if adReward.isZero {
            reason = .none
        } else {
            reason = .watchedRewardedVideo
        }
        return .init(balanceOutOfDateReason: reason,
                     optimisticBalance: libData.balance + adReward,
                     lastRefreshBalance: libData.balance)
    }

    public static func refreshed(
        refreshedData libData: PsiCashLibData, persisted: PsiCashPersistedValues
    ) -> Self {
        persisted.setExpectedPsiCashReward(.zero)
        return .init(balanceOutOfDateReason: .none,
                     optimisticBalance: libData.balance,
                     lastRefreshBalance: libData.balance)
    }

}
