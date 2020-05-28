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
        
        let env = mockIAPEnvironment(
            self.feedbackLogger,
            appReceiptStore: { action in
                guard case .localReceiptRefresh = action else { XCTFatal() }
                return .empty
        })
        
        property("IAPReducer.checkUnverifiedTransaction refreshes local receipt")
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
                return (initState == nextState) && (effectsResults == expectedResult)
        }
        
        // No feedback logs are expected
        XCTAssert(self.feedbackHandler.logs == [])
    }
    
}
