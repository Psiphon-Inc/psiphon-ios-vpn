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

struct SubscriptionState: Equatable {
    var status: SubscriptionStatus
}

extension SubscriptionState {
    init() {
        status = .unknown
    }
}

enum SubscriptionStatus: Equatable {
    case subscribed(SubscriptionData)
    case notSubscribed
    case unknown
}

extension SubscriptionStatus {
    
    var isSubscribed: Bool {
        switch self {
        case .subscribed(_): return true
        case .notSubscribed: return false
        case .unknown: return false
        }
    }
    
}

enum SubscriptionAction {
    case updatedReceiptData(ReceiptData?)
    case timerFinished(withExpiry:Date)
}

typealias SubscriptionReducerEnvironment = (
    notifier: Notifier,
    sharedDB: PsiphonDataSharedDB,
    userConfigs: UserDefaultsConfig,
    appReceiptStore: (ReceiptStateAction) -> Effect<Never>
)

func subscriptionReducer(
    state: inout SubscriptionState, action: SubscriptionAction,
    environment: SubscriptionReducerEnvironment
) -> [Effect<SubscriptionAction>] {
    switch action {
    case .updatedReceiptData(let receipt):
        var effects = [Effect<SubscriptionAction>]()
        effects.append(updatePersistedData(receipt: receipt, environment: environment).mapNever())
        
        guard let receipt = receipt, let subscription = receipt.subscription else {
                state.status = .notSubscribed
                return effects
        }
        
        let intervalToExpired = subscription.latestExpiry.timeIntervalSinceNow
        guard intervalToExpired > SubscriptionHardCodedValues.subscriptionUIMinTime else {
            state.status = .notSubscribed
            return effects
        }
        
        state.status = .subscribed(subscription)
        
        // Notifies extension to run a subscription check if subscription does not
        // expire with `subscriptionCheckMinTime`.
        if intervalToExpired > SubscriptionHardCodedValues.subscriptionCheckMinTime {
            effects.append(
                .fireAndForget {
                    environment.notifier.post(NotifierForceSubscriptionCheck)
                }
            )
        }
        
        effects.append(
            singleFireTimer(interval: intervalToExpired, leeway: SubscriptionHardCodedValues.leeway)
                .map { _ in .timerFinished(withExpiry: subscription.latestExpiry)
            }
        )
        
        return effects
        
    case .timerFinished(withExpiry: let expiry):
        /// In case of a race condition where an `.updatedReceiptData` action is received
        /// immediately before a `.timerFinishedWithExpiry`, the expiration dates
        /// are compared.
        /// If the current subscription data has a later expiry date than the expiry date in
        /// `.timerFinished` associated value, then we ignore the message.
        guard case let .subscribed(subscription) = state.status else {
            return []
        }
        
        let timerExpiry: TimeInterval = expiry.timeIntervalSinceNow
        let subscriptionExpiry: TimeInterval = subscription.latestExpiry.timeIntervalSinceNow
        let tolerance = SubscriptionHardCodedValues.subscriptionTimerDiffTolerance
        
        // Changes state to `.notSubscribed` only if timers expiry matches
        // current subscription expiry value.
        if abs(timerExpiry - subscriptionExpiry) < tolerance {
            state.status = .notSubscribed
        }
        
        return [
            environment.appReceiptStore(.remoteReceiptRefresh(optinalPromise: nil)).mapNever()
        ]
    }
}

// MARK: Effects

/// Updates `UserDefaultsConfig` and `PsiphonDataSharedDB` based on the `data`.
func updatePersistedData(
    receipt data: ReceiptData?, environment: SubscriptionReducerEnvironment
) -> Effect<Never> {
    .fireAndForget {
        guard let data = data else {
            environment.sharedDB.setContainerEmptyReceiptFileSize(NSNumber(integerLiteral: 0))
            return
        }

        guard let subscription = data.subscription else {
            environment.sharedDB.setContainerEmptyReceiptFileSize(data.fileSize as NSNumber)
            return
        }

        // The receipt contains purchase data, reset value in the shared DB.
        environment.sharedDB.setContainerEmptyReceiptFileSize(.none)
        environment.sharedDB.setContainerLastSubscriptionReceiptExpiryDate(subscription.latestExpiry)
    }
}

/// - Note: This function delivers its events on the main dispatch queue.
/// - Important: Sub-millisecond precision is lost in the current implementation.
func singleFireTimer(interval: TimeInterval, leeway: DispatchTimeInterval) -> Effect<()> {
    SignalProducer.timer(interval: DispatchTimeInterval.milliseconds(Int(interval * 1000)),
                         on: QueueScheduler.main,
                         leeway: leeway)
        .map(value: ())
        .take(first: 1)
}
