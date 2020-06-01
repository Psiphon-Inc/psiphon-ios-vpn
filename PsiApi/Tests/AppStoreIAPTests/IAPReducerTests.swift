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
import XCTest
import PsiCashClient
import Testing
import ReactiveSwift
import StoreKit
import SwiftCheck
@testable import PsiApiTestingCommon
@testable import PsiApi
@testable import AppStoreIAP

extension IAPPurchasableProduct {
    
    static let psiCashProduct = IAPPurchasableProduct.arbitrary.suchThat {
        guard case .psiCash(product: _) = $0 else {
            return false
        }
        return true
    }
    
}

extension IAPReducerState {
    
    // nonPurchasingState satisfies the following condition:
    //
    // state.iap.purchasing.completed &&
    //  state.iap.unverifiedPsiCashTx == nil &&
    //  state.psiCashAuth.hasMinimalTokens
    //
    static let nonPurchasingState = Gen<IAPReducerState>.compose { c in
        IAPReducerState(
            iap: IAPState(
                unverifiedPsiCashTx: nil,
                purchasing: c.generate(using:
                    IAPPurchasingState.arbitrary.suchThat { $0.completed })
            ),
            psiCashBalance: c.generate(),
            psiCashAuth: PsiCashAuthPackage.completeAuthPackage
        )
    }
    
    // pendingPurchaseState satisfies the following condition:
    //
    // state.iap.purchasing == .pending
    //
    static let pendingPurchaseState = Gen<IAPReducerState>.compose { c in
        IAPReducerState(
            iap: IAPState(
                unverifiedPsiCashTx: c.generate(),
                purchasing: .pending(c.generate())
            ),
            psiCashBalance: c.generate(),
            psiCashAuth: c.generate()
        )
    }
    
    // pendingPurchaseState satisfies the following condition:
    //
    // state.iap.purchasing.completed &&
    //  state.iap.unverifiedPsiCashTx != nil
    //
    static let pendingVerificationPurchaseState = Gen<IAPReducerState>.compose { c in
        IAPReducerState(
            iap: IAPState(
                unverifiedPsiCashTx: c.generate(using:
                    UnverifiedPsiCashTransactionState.arbitrary),
                purchasing: c.generate(using:
                    IAPPurchasingState.arbitrary.suchThat { $0.completed })
            ),
            psiCashBalance: c.generate(),
            psiCashAuth: c.generate()
        )
    }
    
    // missingPsiCashPurchaseState satisfies the following condition:
    //
    // state.iap.purchasing.completed &&
    //  state.iap.unverifiedPsiCashTx == nil &&
    //  !(state.psiCashAuth.hasMinimalTokens)
    static let missingPsiCashPurchaseState = Gen<IAPReducerState>.compose { c in
        IAPReducerState(
            iap: IAPState(
                unverifiedPsiCashTx: nil,
                purchasing: c.generate(using:
                    IAPPurchasingState.arbitrary.suchThat { $0.completed })
            ),
            psiCashBalance: c.generate(),
            psiCashAuth: PsiCashAuthPackage(withTokenTypes: [])
        )
    }
    
}

final class IAPReducerTests: XCTestCase {
    
    let args = CheckerArguments()
    var feedbackHandler: ArrayFeedbackLogger!
    var feedbackLogger: FeedbackLogger!
    
    override func setUpWithError() throws {
        feedbackHandler = ArrayFeedbackLogger()
        feedbackLogger = FeedbackLogger(feedbackHandler)
    }
    
    override func tearDownWithError() throws {
        feedbackLogger = nil
    }
    
    func testCheckUnverifiedTransaction() {
        
        let env = mockIAPEnvironment(
            self.feedbackLogger,
            appReceiptStore: { action in
                guard case .localReceiptRefresh = action else { XCTFatal() }
                return .empty
        })
        
        property("IAPReducer.checkUnverifiedTransaction refreshes local receipt", arguments: args)
            <- forAll { (initState: IAPReducerState) in
                
                // Arrange
                let expectedResult: [SignalProducer<IAPAction, Never>.CollectedEvents]
                if initState.iap.unverifiedPsiCashTx != nil {
                    expectedResult = [[.completed]]
                } else {
                    expectedResult = []
                }
                                
                // Act
                let (nextState, effectsResults) = testReducer(initState,
                                                              .checkUnverifiedTransaction,
                                                              env, iapReducer)
                
                // Assert
                return (initState ==== nextState) ^&&^ (effectsResults ==== expectedResult)
        }
        
        // No feedback logs are expected
        XCTAssert(self.feedbackHandler.logs == [])
    }
    
    func testPurchase() {

        // A single reference is enough for testing since this object is immutable and created
        // by the SDK.
        let mockPayment = SKPayment()
        
        let env = mockIAPEnvironment(
            self.feedbackLogger,
            paymentQueue: PaymentQueue.mock(addPayment: { product -> AddedPayment in
                return AddedPayment(product, mockPayment)
            }))
       
        
        property("""
            IAPReducer.purchase adds purchase given that: there are no pending transactions, \
            if the transaction is a consumable, that there are no consumables pending verification \
            by the purchase-verifier server, and if the transaction is a PsiCash transaction that \
            it has minimal tokens to purchase PsiCash
            """, arguments: args)
            <-
            forAll(IAPReducerState.nonPurchasingState, IAPPurchasableProduct.arbitrary) {
                (initState: IAPReducerState, product: IAPPurchasableProduct) in
                
                // Test
                let (nextState, effectsResults) = testReducer(initState, .purchase(product),
                                                              env, iapReducer)
                
                return (initState.iap.purchasing.completed) <?> "Init state"
                    ^&&^
                    (nextState.iap.purchasing ==== .pending(product)) <?> "State is pending"
                    ^&&^
                    (effectsResults ==== [[.value(._purchaseAdded(AddedPayment(product, mockPayment))),
                                         .completed]]) <?> "Effect result added purchase"
                    ^&&^
                    (self.feedbackHandler.logs ==== []) <?> "Feedback logs"
        }
    
        
        property("IAPReducer.purchase results in no-op if there is pending purchase",
                 arguments: args)
            <-
            forAll(IAPReducerState.pendingPurchaseState, IAPPurchasableProduct.arbitrary) {
                (initState: IAPReducerState, product: IAPPurchasableProduct) in

                let (nextState, effectsResults) = testReducer(initState, .purchase(product),
                                                              env, iapReducer)
                
                return (nextState ==== initState) <?> "State unchanged"
                    ^&&^
                    (effectsResults ==== []) <?> "No effects"
                    ^&&^
                    (self.feedbackHandler.logs ==== []) <?> "Feedback logs"
        }
    
        
        property("IAPReducer.purchase results in no-op if there is consumable pending verification",
                 arguments: args)
            <-
            forAll(IAPReducerState.pendingVerificationPurchaseState,
                   IAPPurchasableProduct.psiCashProduct) {
                (initState: IAPReducerState, product: IAPPurchasableProduct) in
                
                // Test
                let (nextState, effectsResults) = testReducer(initState, .purchase(product),
                                                              env, iapReducer)
                                
                return (nextState ==== initState) <?> "State unchanged"
                    ^&&^
                    (effectsResults ==== []) <?> "No effects"
                    ^&&^
                    (self.feedbackHandler.logs ==== []) <?> "Feedback logs"
        }
        
        property("IAPReducer.purchase results in purchase error if PsiCash tokens are missing",
                 arguments: args)
            <-
            forAll(IAPReducerState.missingPsiCashPurchaseState,
                   IAPPurchasableProduct.psiCashProduct) {
                (initState: IAPReducerState, product: IAPPurchasableProduct) in
                
                // Test
                let (nextState, effectsResults) = testReducer(initState, .purchase(product),
                                                              env, iapReducer)
                                
                guard case .error(let errorEvent) = nextState.iap.purchasing,
                    case .failedToCreatePurchase(reason: "PsiCash data not present.") =
                    errorEvent.error else {
                    return false
                }
                
                return (effectsResults ==== [[.completed]]) <?> "Feedback effect"
                    ^&&^
                    (self.feedbackHandler.logs[0].level ==== .nonFatal(.error)) <?> "Feedback logs"
                    ^&&^
                    (self.feedbackHandler.logs[0].message ==== "PsiCash IAP purchase without tokens")
                        <?> "Feedback logs message"
        }
        
    }
    
}
