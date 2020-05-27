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
@testable import PsiApiTestingCommon
@testable import PsiApi
@testable import AppStoreIAP

final class IAPReducerTests: XCTestCase {
    
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
        
        let test = { (description: String,
            unverifiedPsiCashTx: UnverifiedPsiCashTransactionState?,
            expectedEffectsResults: [[Signal<IAPAction, SignalProducer<IAPAction, Never>.SignalError>.Event]]) in
            
            // Arrange
            var iapState = IAPState()
            iapState.unverifiedPsiCashTx = unverifiedPsiCashTx
            
            let initState = IAPReducerState(
                iap: iapState,
                psiCashBalance: PsiCashBalance(),
                psiCashAuth: PsiCashAuthPackage(withTokenTypes: [])
            )
            
            let env = mockIAPEnvironment(
                self.feedbackLogger,
                appReceiptStore: { action in
                    guard case .localReceiptRefresh = action else { XCTFatal() }
                    return .empty
            })
            
            // Act
            let (nextState, effectsResults) = testReducer(initState, .checkUnverifiedTransaction,
                                                          env, iapReducer)
            
            // Assert
            XCTAssert(initState == nextState, description)
            XCTAssert(
                effectsResults == expectedEffectsResults,
                "'\(description)' Expected '\(expectedEffectsResults)' Got '\(effectsResults)'"
            )
        }
        
        // Tests
        
        test("no unverified consumable",
            nil, [])
        
        test("one unverified consumable - not requested",
            UnverifiedPsiCashTransactionState(
                transaction: PaymentTransaction.mock(),
                verificationState: .notRequested
            ),
            [[.completed]]
        )
        
        test("one unverified - pending request",
            UnverifiedPsiCashTransactionState(
                transaction: PaymentTransaction.mock(),
                verificationState: .pendingVerificationResult
            ),
            [[.completed]]
        )
        
        test("one unverified - request error",
            UnverifiedPsiCashTransactionState(
                transaction: PaymentTransaction.mock(),
                verificationState: .requestError(ErrorEvent(ErrorRepr(repr: "")))
            ),
            [[.completed]]
        )
        
        // No feedback logs are expected
        XCTAssert(self.feedbackHandler.logs == [])
    }
    
}
