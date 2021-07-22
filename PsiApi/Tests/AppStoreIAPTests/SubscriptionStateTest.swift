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
            
            let result = runSubscriptionReducer(effectsTimeout: 10,
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
        
        // Arrange
        let receipt = ReceiptData.mock(subscriptionInAppPurchases: [])
        
        // Act
        let result = runSubscriptionReducer(effectsTimeout: 10,
                                            subscriptionStatus: .unknown,
                                            subscriptionAction: .updatedReceiptData(receipt))
        
        // Assert
        XCTAssertEqual(result.subscriptionActions, [])
        XCTAssertEqual(result.receiptStateActions.count, 0)
        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.notSubscribed)
    }
    
    /// Expect subscription status to switch to `notSubscribed` since there are no
    /// active subscription purchases in the receipt.
    func testSubscriptionExpired() {
        
        // Arrange
        let iap = iapPurchase(purchaseDate: Date(),
                              expires: Date(timeInterval: -10, since: Date()))
        
        let receipt = ReceiptData.mock(subscriptionInAppPurchases: [iap])
        
        // Act
        let result = runSubscriptionReducer(effectsTimeout: 0,
                                            subscriptionStatus: .unknown,
                                            subscriptionAction: .updatedReceiptData(receipt))
        
        // Assert
        XCTAssertEqual(result.subscriptionActions, [])
        XCTAssertEqual(result.receiptStateActions.count, 0)
        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.notSubscribed)
    }
    
    /// Expect subscription status to switch to `notSubscribed` since there is an active
    /// subscription in the receipt, but time remaining is not greater than the leeway in the reducer.
    func testSubscriptionExpiredByLeeway() {
        
        // Arrange
        let iap = iapPurchase(purchaseDate: Date(),
                              expires: Date(timeInterval: 5,
                                            since: Date()))
        
        let receipt = ReceiptData.mock(subscriptionInAppPurchases: [iap])
        
        // Act
        let result = runSubscriptionReducer(effectsTimeout: 0,
                                            subscriptionStatus: .unknown,
                                            subscriptionAction: .updatedReceiptData(receipt))
        
        XCTAssertEqual(result.subscriptionActions, [])
        XCTAssertEqual(result.receiptStateActions.count, 0)
        XCTAssertEqual(result.subscriptionState.status, SubscriptionStatus.notSubscribed)
    }
    
    /// Expect subscription status to be `subscribed` since there is an active subscription
    /// purchase in the receipt.
    func testSubscribedSingleIAP() {
        
        // Arrange
        let expiryDate = Date(timeInterval: 10, since: Date())
        let iap = iapPurchase(purchaseDate: Date(),
                              expires: expiryDate)
        
        let receipt = ReceiptData.mock(subscriptionInAppPurchases: [iap])
        
        // Act
        let result = runSubscriptionReducer(effectsTimeout: 15,
                                            subscriptionStatus: .unknown,
                                            subscriptionAction: .updatedReceiptData(receipt))
        
        // Assert
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
        
        // Arrange
        let currentSubscriptionExpiryDate = Date(timeInterval: 10, since: Date())
        let currentSubscription = iapPurchase(purchaseDate: Date(),
                                              expires: currentSubscriptionExpiryDate)
        
        let iaps: Set<SubscriptionIAPPurchase> =
            [iapPurchase(purchaseDate: Date(),
                         expires: Date(timeInterval: -10, since: Date())),
             iapPurchase(purchaseDate: Date(),
                         expires: Date(timeInterval: -60*60*24, since: Date())),
             currentSubscription]
        
        let receipt = ReceiptData.mock(subscriptionInAppPurchases: iaps)
        
        // Act
        let result = runSubscriptionReducer(
            effectsTimeout: 15,
            subscriptionStatus: .unknown,
            subscriptionAction: .updatedReceiptData(receipt))
        
        // Assert
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
        
        let result = runSubscriptionReducer(effectsTimeout: 5,
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
        
        let result = runSubscriptionReducer(effectsTimeout: 10,
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
            
            let result = runSubscriptionReducer(effectsTimeout: 0,
                                                subscriptionStatus: subscriptionStatus,
                                                subscriptionAction: ._timerFinished(withExpiry: Date()))
            
            XCTAssertEqual(result.subscriptionActions, [])
            XCTAssertEqual(result.receiptStateActions.count, 0)
            XCTAssertEqual(result.subscriptionState.status, subscriptionStatus)
        }
    }
    
}

// MARK: Helper functions

/// Generates IAP purchase with unique ID.
fileprivate func iapPurchase(purchaseDate: Date, expires: Date) -> SubscriptionIAPPurchase {
    SubscriptionIAPPurchase(
        productID: ProductID(rawValue: "com.test.subscription1")!,
        transactionID: TransactionID(rawValue: UUID().uuidString)!,
        originalTransactionID: OriginalTransactionID(rawValue: "12345678")!,
        webOrderLineItemID: WebOrderLineItemID(rawValue: "100012345678")!,
        purchaseDate: purchaseDate,
        expires: expires,
        isInIntroOfferPeriod: false,
        hasBeenInIntroOfferPeriod: false
    )
}

fileprivate struct ReducerOutputs {
    let subscriptionState: SubscriptionState
    let subscriptionActions:
        [[Signal<SubscriptionAction, SignalProducer<SubscriptionAction, Never>.SignalError>.Event]]
    let receiptStateActions: [ReceiptStateAction]
}

/// Runs `subscriptionReducer` with given parameters.
fileprivate func runSubscriptionReducer(
    effectsTimeout: TimeInterval,
    subscriptionStatus: SubscriptionStatus,
    subscriptionAction: SubscriptionAction
) -> ReducerOutputs {
    
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
        dateCompare: DateCompare.mock,
        singleFireTimer: { _,_ in SignalProducer(value: ())} // fire timer immediately
    )
    
    var subscriptionState: SubscriptionState = SubscriptionState()
    subscriptionState.status = subscriptionStatus
    
    let (nextSubscriptionState, effectsResults) =
        testReducer(subscriptionState, subscriptionAction, env, subscriptionTimerReducer, effectsTimeout)
    
    return ReducerOutputs(subscriptionState: nextSubscriptionState,
                          subscriptionActions: effectsResults,
                          receiptStateActions: receiptStateActions)
    
}
