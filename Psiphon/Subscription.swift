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

// TODO: store and recover this struct instead of the subscription dictionary
struct SubscriptionData: Equatable, Codable {
    let latestExpiry: Date
    let productId: String
    let hasBeenInIntroPeriod: Bool

    // Enum values match dictionary keys defined in "AppStoreReceiptData.h"
    private enum ReceiptFields: String {
        case appReceiptFileSize = "app_receipt_file_size"
        case latestExpirationDate = "latest_expiration_date"
        case productId = "product_id"
        case hasBeenInIntroPeriod = "has_been_in_intro_period"
    }

    static func fromSubsriptionDictionary(_ dict: [String: Any]) -> SubscriptionData? {
        guard let expiration = dict[ReceiptFields.latestExpirationDate] as? Date else {
            return .none
        }
        guard let productId = dict[ReceiptFields.productId] as? String else {
            return .none
        }
        guard let introPeriod = dict[ReceiptFields.hasBeenInIntroPeriod] as? Bool else {
            return .none
        }
        return SubscriptionData(latestExpiry: expiration, productId: productId,
                                hasBeenInIntroPeriod: introPeriod)
    }
}

enum SubscriptionAction {
    case updatedReceiptData(Receipt?)
    case timerFinished(withExpiry:Date)
}

func subscriptionReducer(
    state: inout SubscriptionState, action: SubscriptionAction
) -> [Effect<SubscriptionAction>] {
    switch action {
    case .updatedReceiptData(let receipt):
        var effects = [Effect<SubscriptionAction>]()
        effects.append(updatePersistedData(receipt: receipt).mapNever())
        
        guard let receipt = receipt, let subscription = receipt.subscription else {
                state.status = .notSubscribed
                return effects
        }
        
        let intervalToExpired = subscription.latestExpiry.timeIntervalSinceNow
        guard intervalToExpired > Current.hardCodedValues.subscription.subscriptionUIMinTime else {
            state.status = .notSubscribed
            return effects
        }
        
        state.status = .subscribed(subscription)
        
        // Notifies extension to run a subscription check if subscription does not
        // expire with `subscriptionCheckMinTime`.
        if intervalToExpired > Current.hardCodedValues.subscription.subscriptionCheckMinTime {
            effects.append(
                .fireAndForget {
                    Current.notifier.post(NotifierForceSubscriptionCheck)
                }
            )
        }
        
        effects.append(
            singleFireTimer(interval: intervalToExpired,
                            leeway: Current.hardCodedValues.subscription.leeway)
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
        
        // Changes state to `.notSubscribed` only if timers expiry matches
        // current subscription expiry value.
        if expiry.timeIntervalSinceNow.isAlmostEqual(to:
            subscription.latestExpiry.timeIntervalSinceNow) {
            state.status = .notSubscribed
        }
        
        return []
    }
}

// MARK: Effects

/// Updates `UserDefaultsConfig` and `PsiphonDataSharedDB` based on the `data`.
func updatePersistedData(receipt data: Receipt?) -> Effect<Never> {
    .fireAndForget {
        guard let data = data else {
            Current.sharedDB.setContainerEmptyReceiptFileSize(NSNumber(integerLiteral: 0))
            return
        }

        guard let subscription = data.subscription else {
            Current.sharedDB.setContainerEmptyReceiptFileSize(data.fileSize as NSNumber)
            return
        }

        Current.userConfigs.subscriptionData = subscription

        // The receipt contains purchase data, reset value in the shared DB.
        Current.sharedDB.setContainerEmptyReceiptFileSize(.none)
        Current.sharedDB.setContainerLastSubscriptionReceiptExpiryDate(subscription.latestExpiry)
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
