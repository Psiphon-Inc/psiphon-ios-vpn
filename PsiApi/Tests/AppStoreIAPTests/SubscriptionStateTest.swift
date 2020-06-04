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

import XCTest
import ReactiveSwift
import SwiftCheck
import Testing
@testable import PsiApi
@testable import AppStoreIAP
@testable import PsiApiTestingCommon

final class SubscriptionStateTest: XCTestCase {

    func testWithSwiftCheck() {

        property("Subscription Reducer") <- forAll { (action: SubscriptionAction, status: SubscriptionStatus) in

            // Since status is mutated
            let originalStatus = status

            let result = SubscriptionStateTest.runReducer(effectsTimeout: 10,
                                                          subscriptionStatus: status,
                                                          subscriptionAction: action)

            switch (action, originalStatus) {
            case (._timerFinished(let expiry), .subscribed(let iap)):

                if abs(expiry.timeIntervalSinceNow - iap.expires.timeIntervalSinceNow) < 1.0 {
                    // Status is set to not subscribed if the timer and subscription
                    // IAP expire at approximately the same time.
                    if result.subscriptionState.status != .notSubscribed {
                        return false
                    }
                } else if result.subscriptionState.status != originalStatus {
                    // Otherwise status will not have been changed.
                    return false
                }

                if (result.subscriptionActions != [[.completed], [.completed]]) {
                    return false
                }

                if (result.receiptStateActions.count != 1) {
                    return false
                }

                // Expect a remote receipt refresh action
                let action = result.receiptStateActions[0]
                switch action {
                    case .remoteReceiptRefresh(optionalPromise: _):
                        break
                    default:
                        return false
                }

                return true

            case (._timerFinished(_), _):
                // No purchase present so status will be unchanged.

                if result.receiptStateActions.count != 0 {
                    return false
                }

                if result.subscriptionActions.count != 0 {
                    return false
                }

                return result.subscriptionState.status == originalStatus
            case (.updatedReceiptData(let data), _):
                switch (result.subscriptionState.status) {
                case .unknown:
                    // Should never result in a status of unknown.
                    return false
                case .notSubscribed:
                    // Status is always set in this branch of the reducer.

                    // There should be no effects
                    if result.subscriptionActions.count != 0 {
                        return false
                    }

                    guard let receipt = data else {
                        return true
                    }

                    guard let purchaseWithLatestExpiry = receipt.subscriptionInAppPurchases.sortedByExpiry().last else {
                        return true
                    }

                    let isExpired = isApproximatelyExpired(date: purchaseWithLatestExpiry.expires)

                    guard !isExpired else {
                        return true
                    }

                    let timeLeft = purchaseWithLatestExpiry.expires.timeIntervalSinceNow

                    guard timeLeft > 5 else {
                        return true
                    }

                    // The status should actually be subscribed.
                    return false
                case .subscribed(let iap):

                    // Check that there is a active subscription IAP
                    // in the receipt.

                    guard let receipt = data else {
                        return false
                    }

                    guard let purchaseWithLatestExpiry = receipt.subscriptionInAppPurchases.sortedByExpiry().last else {
                        return false
                    }

                    let isExpired = isApproximatelyExpired(date: purchaseWithLatestExpiry.expires)

                    guard !isExpired else {
                        return false
                    }

                    let timeLeft = purchaseWithLatestExpiry.expires.timeIntervalSinceNow

                    guard timeLeft > 5 else {
                        return false
                    }

                    if result.subscriptionActions != [[.value(._timerFinished(withExpiry: iap.expires)),
                                                       .completed], // logging effect
                                                      [.completed]] {
                        return false
                    }

                    return true
                }
            }
        }
    }

    // MARK: .updatedReceiptData tests

    /// Expect subscription status to switch to `notSubscribed` since there are no
    /// subscription purchases in the receipt.
    func testSubscriptionIAPs() {

        let result = SubscriptionStateTest.runReducer(effectsTimeout: 10, iaps: [])

        XCTAssertEqual(result.subscriptionActions, [])
        XCTAssertEqual(result.receiptStateActions.count, 0)
        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.notSubscribed)
    }

    /// Expect subscription status to switch to `notSubscribed` since there are no
    /// active subscription purchases in the receipt.
    func testSubscriptionExpired() {

        let iap = iapPurchase(purchaseDate: Date(),
                              expires: Date(timeInterval: -10,
                                            since: Date()))

        let result = SubscriptionStateTest.runReducer(effectsTimeout: 0, iaps: [iap])

        XCTAssertEqual(result.subscriptionActions, [])
        XCTAssertEqual(result.receiptStateActions.count, 0)
        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.notSubscribed)
    }

    /// Expect subscription status to switch to `notSubscribed` since there is an active
    /// subscription in the receipt, but time remaining is not greater than the leeway in the reducer.
    func testSubscriptionExpiredByLeeway() {

        let iap = iapPurchase(purchaseDate: Date(),
                              expires: Date(timeInterval: 5,
                                            since: Date()))

        let result = SubscriptionStateTest.runReducer(effectsTimeout: 0, iaps: [iap])

        XCTAssertEqual(result.subscriptionActions, [])
        XCTAssertEqual(result.receiptStateActions.count, 0)
        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.notSubscribed)
    }

    /// Expect subscription status to be `subscribed` since there is an active subscription
    /// purchase in the receipt.
    func testSubscribedSingleIAP() {

        let expiryDate = Date(timeInterval: 10,
                              since: Date())

        let iap = iapPurchase(purchaseDate: Date(), expires: expiryDate)

        let result = SubscriptionStateTest.runReducer(effectsTimeout: 15, iaps: [iap])

        XCTAssertEqual(result.subscriptionActions,
                       [[.value(._timerFinished(withExpiry: expiryDate)),
                         .completed], // logging effect
                        [.completed]]) // collect
        XCTAssertEqual(result.receiptStateActions.count, 0)
        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.subscribed(iap))
    }

    /// Expect subscription status to be `subscribed` since there is an active subscription
    /// purchase in the receipt. Expired subscription purchases should be ignored by the reducer.
    func testSubscribedMultipleIAPs() {

        let currentSubscriptionExpiryDate = Date(timeInterval: 10,
                                                 since: Date())
        let currentSubscription = iapPurchase(purchaseDate: Date(),
                                              expires: currentSubscriptionExpiryDate)

        let iaps: Set<SubscriptionIAPPurchase> =
            [iapPurchase(purchaseDate: Date(),
                         expires: Date(timeInterval: -10, since: Date())),
             iapPurchase(purchaseDate: Date(),
                         expires: Date(timeInterval: -60*60*24, since: Date())),
             currentSubscription]

        let result = SubscriptionStateTest.runReducer(effectsTimeout: 15, iaps: iaps)

        XCTAssertEqual(result.subscriptionActions,
                       [[.value(._timerFinished(withExpiry: currentSubscriptionExpiryDate)),
                         .completed], // logging effect
                        [.completed]]) // collect
        XCTAssertEqual(result.receiptStateActions.count, 0)
        XCTAssertEqual(result.subscriptionState.status,
                       SubscriptionStatus.subscribed(currentSubscription))
    }

    // MARK: .timerFinished tests

    /// Expect timer to fire when IAP expires and subscription status to be `notSubscribed` since
    /// the subscription expires approximately when the timer fires.
    func testTimerExpiredIAPExpired() {

        let iap = iapPurchase(purchaseDate: Date(timeInterval: -60*60*24,
                                                 since: Date()),
                              expires: Date(timeInterval: 0,
                                            since: Date()))

        let subscriptionStatus: SubscriptionStatus = .subscribed(iap)

        let result = SubscriptionStateTest.runReducer(effectsTimeout: 5,
                                                      subscriptionStatus: subscriptionStatus,
                                                      subscriptionAction: ._timerFinished(withExpiry: Date()))

        XCTAssertEqual(result.subscriptionActions, [[.completed], [.completed]])

        if (result.receiptStateActions.count != 1) {
            XCTFail("Expected 1 receipt state action but got \(result.receiptStateActions.count)")
        } else {
            let action = result.receiptStateActions[0]
            switch action {
            case .remoteReceiptRefresh(optionalPromise: _):
                break
            default:
                XCTFail("Expected remote receipt refresh, but got: \(action)")
            }
        }

        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.notSubscribed)
    }

    /// Expect time to fire when IAP expires and subscription status to be `subscribed` since the
    /// subscription does *not* expire approximately when the timer expires.
    func testTimerExpiredIAPNotExpired () {
        let iap = iapPurchase(purchaseDate: Date(),
                              expires: Date(timeInterval: 10,
                                            since: Date()))

        let subscriptionStatus: SubscriptionStatus = .subscribed(iap)

        let result = SubscriptionStateTest.runReducer(effectsTimeout: 10,
                                                      subscriptionStatus: subscriptionStatus,
                                                      subscriptionAction: ._timerFinished(withExpiry: Date()))

        XCTAssertEqual(result.subscriptionActions, [[.completed], [.completed]])

        if (result.receiptStateActions.count != 1) {
            XCTFail("Expected 1 receipt state action but got \(result.receiptStateActions.count)")
        } else {
            let action = result.receiptStateActions[0]
            switch action {
            case .remoteReceiptRefresh(optionalPromise: _):
                break
            default:
                XCTFail("Expected remote receipt refresh, but got: \(action)")
            }
        }

        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.subscribed(iap))
    }

    /// Expect subscription status to not change when the timer fires since there are no active subscription purchases.
    func testTimerExpiredNoIAPs() {

        let subscriptionStatuses: [SubscriptionStatus] = [.unknown, .notSubscribed]

        for subscriptionStatus in subscriptionStatuses {

            let result = SubscriptionStateTest.runReducer(effectsTimeout: 0,
                                                          subscriptionStatus: subscriptionStatus,
                                                          subscriptionAction: ._timerFinished(withExpiry: Date()))

            XCTAssertEqual(result.subscriptionActions, [])
            XCTAssertEqual(result.receiptStateActions.count, 0)
            XCTAssertEqual(result.subscriptionState.status, subscriptionStatus)
        }
    }

    // MARK: test helpers

    struct ReducerOutputs {
        let subscriptionState: SubscriptionState
        let subscriptionActions:
            [[Signal<SubscriptionAction,
                    SignalProducer<SubscriptionAction, Never>.SignalError>
            .Event]]
        let receiptStateActions: [ReceiptStateAction]
    }

    /// Generates IAP purchase with unique ID.
    func iapPurchase(purchaseDate: Date, expires: Date) -> SubscriptionIAPPurchase {
        return SubscriptionIAPPurchase(productID: "com.test.subscription1",
                                       transactionID: TransactionID(stringLiteral: UUID().uuidString),
                                       originalTransactionID: "12345678",
                                       purchaseDate: purchaseDate,
                                       expires: expires,
                                       isInIntroOfferPeriod: false,
                                       hasBeenInIntroOfferPeriod: false)
    }

    /// Tests reducer with given subscription IAPs.
    static func runReducer(effectsTimeout: TimeInterval,
                           iaps: Set<SubscriptionIAPPurchase>) -> ReducerOutputs {

        // NOTE: ReceiptData.parseLocalReceipt is unused because we forgo constructing
        // the ASN.1 receipt data.
        let receiptData: ReceiptData =
            ReceiptData(subscriptionInAppPurchases: iaps,
                        consumableInAppPurchases: [],
                        data: Data(), // unused: see note above
                readDate: Date())

        let subscriptionAction: SubscriptionAction = .updatedReceiptData(receiptData)

        return runReducer(effectsTimeout: effectsTimeout,
                          subscriptionStatus: .unknown,
                          subscriptionAction: subscriptionAction)
    }

    /// Run reducer with given parameters.
    static func runReducer(effectsTimeout: TimeInterval,
                           subscriptionStatus: SubscriptionStatus,
                           subscriptionAction: SubscriptionAction) -> ReducerOutputs {

        // output logs to stdout
        let feedbackLogger: FeedbackLogger = FeedbackLogger(StdoutFeedbackLogger())

        var receiptStateActions: [ReceiptStateAction] = []

        let env = SubscriptionReducerEnvironment(
            feedbackLogger: feedbackLogger,
            appReceiptStore: { (action: ReceiptStateAction) -> Effect<Never> in
                .fireAndForget {
                    receiptStateActions.append(action)
                }
            },
            getCurrentTime: {
                return Date()
            },
            compareDates: { date1, date2, _ -> ComparisonResult in
                // NOTE: overrides granularity set by reducer for second level granularity.
                return compareDates(date1, to: date2)
            },
            singleFireTimer: { _,_ in SignalProducer(value: ())} // fire timer immediately
        )

        var subscriptionState: SubscriptionState = SubscriptionState()
        subscriptionState.status = subscriptionStatus

        let (nextSubscriptionState, effectsResults) =
            testReducer(subscriptionState, subscriptionAction, env, subscriptionReducer, effectsTimeout)

        return ReducerOutputs(subscriptionState: nextSubscriptionState,
                              subscriptionActions: effectsResults,
                              receiptStateActions: receiptStateActions)

    }
}
