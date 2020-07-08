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
import Utilities
@testable import PsiApiTestingCommon
@testable import PsiApi
@testable import AppStoreIAP


final class IAPReducerTests: XCTestCase {
    
    let args = CheckerArguments()
    var feedbackHandler: ArrayFeedbackLogHandler!
    var feedbackLogger: FeedbackLogger!
    
    override func setUpWithError() throws {
        feedbackHandler = ArrayFeedbackLogHandler()
        feedbackLogger = FeedbackLogger(feedbackHandler)
        Debugging = .disabled()
    }
    
    override func tearDownWithError() throws {
        feedbackLogger = nil
    }
    
    func testCheckUnverifiedTransaction() {
        
        let env = IAPEnvironment.mock(
            self.feedbackLogger,
            appReceiptStore: { action in
                guard case .localReceiptRefresh = action else { XCTFatal() }
                return .empty
        })
        
        property("IAPReducer.checkUnverifiedTransaction refreshes local receipt", arguments: args)
            <- forAll { (initState: IAPReducerState) in
                
                // Arrange
                self.feedbackHandler.logs = []

                let expectedResult: [SignalProducer<IAPAction, Never>.CollectedEvents]
                if initState.iap.unfinishedPsiCashTx != nil {
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
        
        let emptyEnv = IAPEnvironment.mock(self.feedbackLogger)
        
        property("""
            IAPReducer.purchase adds purchase given that: there are no pending transactions, \
            if the transaction is a consumable, that there are no consumables pending verification \
            by the purchase-verifier server, and if the transaction is a PsiCash transaction that \
            it has minimal tokens to purchase PsiCash
            """, arguments: args)
            <-
            forAll(IAPReducerState.arbitraryWithNonPurchasingState, AppStoreProduct.arbitrary, Payment.arbitrary) {
                (initState: IAPReducerState, product: AppStoreProduct, mockPayment: Payment) in
                                
                // Arrange
                self.feedbackHandler.logs = []
                
                let env = IAPEnvironment.mock(
                    self.feedbackLogger,
                    paymentQueue: PaymentQueue.mock(addPayment: { _ in
                        return .empty
                    })
                )
                
                // Act
                let (nextState, effectsResults) = testReducer(
                    initState, .purchase(product: product, resultPromise: nil), env, iapReducer
                )
                
                // Assert
                return (initState.iap.purchasing.values.allSatisfy({ $0.completed })) <?> "Init state"
                    ^&&^
                    (nextState.iap.purchasing[product.type]?.purchasingState ==== .pending(nil)) <?> "State is pending"
                    ^&&^
                    (effectsResults ==== [[.completed]]) <?> "Effect result added purchase"
                    ^&&^
                    (self.feedbackHandler.logs ==== []) <?> "Feedback logs"
        }
    
        
        property("""
            IAPReducer.purchase results in no-op if there is pending purchase
            of the same product type
            """, arguments: args)
            <-
            forAll(IAPReducerState.arbitraryWithPurchasePending) {
                (pair: Pair<IAPReducerState, AppStoreProduct>) in
                
                // Arrange
                let initState = pair.first
                let product = pair.second
                self.feedbackHandler.logs = []
                
                // Act
                let (nextState, effectsResults) = testReducer(
                    initState, .purchase(product: product, resultPromise: nil),
                    emptyEnv, iapReducer
                )
                
                // Assert
                return (nextState ==== initState) <?> "State unchanged"
                    ^&&^
                    (effectsResults ==== [[.completed]]) <?> "Log effect"
                    ^&&^
                    (self.feedbackHandler.logs.count ==== 1) <?> "Feedback logs"
                    ^&&^
                    (self.feedbackHandler.logs[maybe: 0]?.level ==== .nonFatal(.warn))
        }


        property("IAPReducer.purchase results in no-op if there is consumable pending verification",
                 arguments: args)
            <-
            forAll(IAPReducerState.arbitraryWithPendingVerificationPurchaseState,
                   AppStoreProduct.arbitraryPsiCashProduct)
            { (initState: IAPReducerState, product: AppStoreProduct) in
                
                // Arrange
                self.feedbackHandler.logs = []
                
                // Act
                let (nextState, effectsResults) = testReducer(
                    initState, .purchase(product: product, resultPromise: nil),
                    emptyEnv, iapReducer
                )
                
                // Assert
                return (nextState ==== initState) <?> "State unchanged"
                    ^&&^
                    (effectsResults ==== [[.completed]]) <?> "Log effect"
                    ^&&^
                    (self.feedbackHandler.logs.count ==== 1) <?> "Feedback logs"
                    ^&&^
                    (self.feedbackHandler.logs[maybe: 0]?.level ==== .nonFatal(.warn))
        }

        
        property("IAPReducer.purchase results in purchase error if PsiCash tokens are missing",
                 arguments: args)
            <-
            forAll(IAPReducerState.arbitraryWithMissingPsiCashTokens,
                   AppStoreProduct.arbitraryPsiCashProduct)
            { (initState: IAPReducerState, product: AppStoreProduct) in
                
                // Arrange
                self.feedbackHandler.logs = []
                
                let fixedTime = Date()
                let env = IAPEnvironment.mock(self.feedbackLogger,
                                              getCurrentTime: { fixedTime })
                
                // Act
                let (nextState, effectsResults) = testReducer(
                    initState, .purchase(product: product, resultPromise: nil), env, iapReducer)
                
                return conjoin(
                    // If a product with the same type as generated `product` is not being
                    // purchased, then reducer sets the purchasing state for product type
                    // to error indicating there's no psicash token.
                    (initState.iap.purchasing[product.type]?.completed == true) ==> {
                        return (nextState.iap.purchasing[product.type]?.purchasingState ====
                            .completed(ErrorEvent(.failedToCreatePurchase(reason: "PsiCash data not present"), date: fixedTime)))
                            ^&&^
                            (effectsResults ==== [[.completed]]) <?> "Feedback effect"
                            ^&&^
                            (self.feedbackHandler.logs.count ==== 1) <?> "Feedback log count"
                            ^&&^
                            (self.feedbackHandler.logs[maybe: 0]?.level ==== .nonFatal(.error)) <?> "Feedback logs"
                            ^&&^
                            (self.feedbackHandler.logs[maybe: 0]?.message ==== "PsiCash IAP purchase without tokens")
                            <?> "Feedback logs message"
                    },
                    
                    (initState.iap.purchasing[product.type]?.completed == false) ==> {
                        return (initState ==== nextState) <?> "No State change"
                            ^&&^
                            (effectsResults ==== [[.completed]]) <?> "Log effect"
                            ^&&^
                            (self.feedbackHandler.logs.count ==== 1) <?> "Feedback logs"
                            ^&&^
                            (self.feedbackHandler.logs[maybe: 0]?.level ==== .nonFatal(.warn))
                    }
                )

        }
        
    }

    func testReceiptUpdates() {
        
        // Arrange
        let fixedDate = Date()
        
        var env = IAPEnvironment.mock(
            FeedbackLogger(self.feedbackHandler),
            tunnelStatusSignal: SignalProducer(value: .connected),
            tunnelConnectionRefSignal: SignalProducer(value:
                .some(TunnelConnection { .connection(.connected) })),
            psiCashEffects: .mock(rewardedVideoCustomData: String.arbitrary),
            getCurrentTime: { () -> Date in return fixedDate }
        )
        
        property("""
            IAPReducer.receiptUpdated creates a verification request for consumable product
            for which a request has not been sent yet
            """, arguments: args)
            <-
            forAll { (initState: IAPReducerState, receipt: ReceiptData?) in
                
                // Resets feedbackHandler logs before each test.
                self.feedbackHandler.logs = []
                
                let mockHttp = MockHTTPClient(Generator(sequence: [
                    .success(Data())
                ]))
                
                env.httpClient = mockHttp.client
                
                // Act
                let (nextState, effectsResults) = testReducer(initState,
                                                              .receiptUpdated(receipt),
                                                              env, iapReducer)
                
                return conjoin(
                    
                    // IAPReducer.receiptUpdated action does not create a second verification request
                    // for a consumable if one is already pending
                    (initState.iap.unfinishedPsiCashTx?.verification == .pendingResponse) ==> {
                        return (nextState ==== initState) ^&&^ (effectsResults ==== [])
                    },
                    
                    // IAPReducer.receiptUpdated logs error if receipt is nil but there is a
                    // consumable transaction pending verification
                    (initState.iap.unfinishedPsiCashTx != nil &&
                        initState.iap.unfinishedPsiCashTx?.verification != .pendingResponse &&
                        receipt == nil) ==> {
                            
                            var expectedNext = initState
                            expectedNext.iap.unfinishedPsiCashTx = UnfinishedConsumableTransaction(
                                completedTransaction: initState.iap.unfinishedPsiCashTx!.transaction,
                                verificationState: .requestError(
                                    ErrorEvent(ErrorRepr(repr: "nil receipt"), date: fixedDate)
                                )
                            )
                            
                            return (nextState ==== expectedNext)
                                ^&&^
                                (effectsResults ==== [[.completed]]) <?> "Logged event"
                                ^&&^
                                (self.feedbackHandler.logs.count ==== 1)
                                ^&&^
                                (self.feedbackHandler.logs[0].level ==== .nonFatal(.error))
                                ^&&^
                                (self.feedbackHandler.logs[0].message.contains("nil receipt data"))
                    },
                    
                    // IAPReducer.receiptUpdated creates a network request to verify
                    // consumable purchase if all conditions set below are met.
                    (initState.iap.unfinishedPsiCashTx != nil &&
                        initState.iap.unfinishedPsiCashTx?.verification != .pendingResponse &&
                        receipt != nil) ==> {
                            
                            // Before the request is submitted, verificationState is expected
                            // to be in a pending state.
                            var expectedNext = initState
                            expectedNext.iap.unfinishedPsiCashTx = UnfinishedConsumableTransaction(
                                completedTransaction: initState.iap.unfinishedPsiCashTx!.transaction,
                                verificationState: .pendingResponse
                            )
                            
                            let paymentTransaction = initState.iap.unfinishedPsiCashTx!.transaction
                            
                            return (nextState ==== expectedNext)
                                ^&&^
                                (effectsResults ====
                                    [[.value(._psiCashConsumableVerificationRequestResult(
                                        result: .completed(.success(.unit)),
                                        forTransaction: paymentTransaction)),
                                      .completed],
                                     [.completed],
                                     [.completed]]
                                )
                                ^&&^
                                (self.feedbackHandler.logs.count ==== 2)
                    }
                    
                )
        }
        
    }

    func testPsiCashConsumableVerificationRequestResult() {

        let fixedDate = Date()

        var env = IAPEnvironment.mock(
            FeedbackLogger(feedbackHandler),
            tunnelStatusSignal: SignalProducer(value: .connected),
            tunnelConnectionRefSignal: SignalProducer(value:
                .some(TunnelConnection { .connection(.connected) })),
            psiCashEffects: .mock(rewardedVideoCustomData: String.arbitrary),
            psiCashStore: { (action: PsiCashAction) -> Effect<Never> in
                return .empty
            },
            getCurrentTime: { () -> Date in return fixedDate }
        )

        // stateAndPaymentGen generates pair IAPReducerState and PaymentTransaction.
        // PaymentTransaction only sometimes matches the `unfinishedPsiCashTx` field of
        // IAPReducerState.
        let stateAndPaymentGen = Gen.zip(IAPReducerState.arbitrary, PaymentTransaction.arbitrary)
            .flatMap { (state, unexpectedPaymentTransaction) -> Gen<Pair<IAPReducerState, PaymentTransaction>> in
                switch state.iap.unfinishedPsiCashTx {
                case let .some(unverified):
                    return Gen.weighted([
                        (4, Pair(state, unverified.transaction)),
                        (1, Pair(state, unexpectedPaymentTransaction))
                    ])
                case .none:
                    return Gen.pure(Pair(state, unexpectedPaymentTransaction))
                }
        }

        property("""
            IAPReducer._psiCashConsumableVerificationRequestResult updates state and finishes
            consumable transaction after successful verification
            """, arguments: args)
            <-
            forAll(
                stateAndPaymentGen,
                RetriableTunneledHttpRequest<PsiCashValidationResponse>.RequestResult.arbitrary
            ) { stateAndPaymentGen, requestResult -> Testable in

                let initState = stateAndPaymentGen.first
                let paymentTransaction = stateAndPaymentGen.second

                // Resets feedbackHandler logs before each test.
                self.feedbackHandler.logs = []

                let finishTransactionGen = Generator<Effect<Never>>(sequence: [.empty])
                env.paymentQueue = PaymentQueue.mock(
                    finishTransaction: finishTransactionGen.returnNextOrFail())

                // Act
                let action = IAPAction._psiCashConsumableVerificationRequestResult(
                    result: requestResult,
                    forTransaction: paymentTransaction
                )
                let (nextState, effectsResults) = testReducer(initState, action, env, iapReducer)

                // Assert
                return conjoin(
                    // iapReducer causes fatal error if this action is received while the state
                    // contains no consumable transaction.
                    (initState.iap.unfinishedPsiCashTx == nil) ==> {
                        return (nextState ==== initState)
                            ^&&^
                            (effectsResults ==== [])
                            ^&&^
                            (self.feedbackHandler.logs.count ==== 1)
                            ^&&^
                            (self.feedbackHandler.logs[0].level ==== .fatal)
                    },

                    // iapReducer causes fatal error if unfinishedPsiCashTx is not in a pending
                    // state after receiving this action.
                    (initState.iap.unfinishedPsiCashTx != nil &&
                        initState.iap.unfinishedPsiCashTx?.verification != .pendingResponse) ==> {
                            return (nextState ==== initState)
                                ^&&^
                                (effectsResults ==== [])
                                ^&&^
                                (self.feedbackHandler.logs.count ==== 1)
                                ^&&^
                                (self.feedbackHandler.logs[0].level ==== .fatal)
                    },

                    // iapReducer should expect this action to refer to the same unverified
                    // transaction that exists in the state.
                    (initState.iap.unfinishedPsiCashTx != nil &&
                        initState.iap.unfinishedPsiCashTx?.verification == .pendingResponse &&
                        initState.iap.unfinishedPsiCashTx?.transaction != paymentTransaction) ==> {
                            return (nextState ==== initState)
                                ^&&^
                                (effectsResults ==== [])
                                ^&&^
                                (self.feedbackHandler.logs.count ==== 1)
                                ^&&^
                                (self.feedbackHandler.logs[0].level ==== .fatal)
                    },

                    // iapReducer updates states according to verification result,
                    // if state indicates that there is an unverified transaction pending response.
                    (initState.iap.unfinishedPsiCashTx != nil &&
                        initState.iap.unfinishedPsiCashTx?.verification == .pendingResponse &&
                        initState.iap.unfinishedPsiCashTx?.transaction == paymentTransaction) ==> {

                            switch requestResult {
                            case .willRetry(_):
                                return (nextState ==== initState)
                                    ^&&^
                                    // Contains no fatal errors
                                    (!self.feedbackHandler.logs.map(\.level).contains(.fatal))

                            case .failed(let errorEvent):

                                // errorEvent should be reflected in the state.
                                var expectedState = initState
                                expectedState.iap.unfinishedPsiCashTx = UnfinishedConsumableTransaction(
                                    completedTransaction: paymentTransaction,
                                    verificationState: .requestError(errorEvent.eraseToRepr())
                                )

                                return (nextState ==== expectedState)
                                    ^&&^
                                    (self.feedbackHandler.logs.count ==== 1)
                                    ^&&^
                                    // Contains no fatal errors
                                    (!self.feedbackHandler.logs.map(\.level).contains(.fatal))

                            case .completed(let validationResponse):
                                switch validationResponse {
                                case .success(.unit):
                                    var expectedState = initState
                                    expectedState.iap.unfinishedPsiCashTx = nil

                                    return (nextState ==== expectedState)
                                        ^&&^
                                        (finishTransactionGen.exhausted) <?> "Finished transaction"
                                        ^&&^
                                        (self.feedbackHandler.logs.count ==== 1)
                                        ^&&^
                                        (self.feedbackHandler.logs.map(\.level).contains(.nonFatal(.info)))

                                case .failure(let errorEvent):
                                    var expectedState = initState

                                    expectedState.iap.unfinishedPsiCashTx =
                                        UnfinishedConsumableTransaction(
                                            completedTransaction: paymentTransaction,
                                            verificationState: .requestError(errorEvent.eraseToRepr()))

                                    return (nextState ==== expectedState)
                                        ^&&^
                                        (self.feedbackHandler.logs.count ==== 1)
                                        ^&&^
                                        (self.feedbackHandler.logs[0].level ==== .nonFatal(.error))
                                }
                            }
                    }

                )
        }

    }
    
    func testUpdatedTransactionRestoredCompleteTransaction() {
        
        var env = IAPEnvironment.mock(self.feedbackLogger)
        
        property("""
            IAPReducer.transactionUpdate(.restoredCompletedTransactions(error:))
            calls environment.appReceiptStore of updated receipted data after a successful
            restore or logs error of the unsuccessful restore
            """, arguments: args)
        <-
            forAll(IAPReducerState.arbitrary,
                   TransactionUpdate.arbitraryWithOnlyRestoredCompletedTransactionsCase)
            { (initState: IAPReducerState, txUpdate: TransactionUpdate) in
                
                // Sanity-check
                guard case .restoredCompletedTransactions(error: _) = txUpdate else {
                    XCTFatal()
                }
                
                // Arrange
                self.feedbackHandler.logs = []
                var appReceiptStoreActionInputs = [ReceiptStateAction]()
                
                env.appReceiptStore = {
                    appReceiptStoreActionInputs.append($0)
                    return .empty
                }
                
                // The error contained within the transaction update.
                let systemError = txUpdate.restoredCompletedTransactions ?? nil
                
                // Act
                let (nextState, effectsResults) = testReducer(initState,
                                                              .transactionUpdate(txUpdate),
                                                              env, iapReducer)
                
                // Assert
                return conjoin(
                    (systemError == nil) ==> {
                        return (nextState ==== initState) <?> "Unchanged state"
                            ^&&^
                            (effectsResults ==== [[.completed]]) <?> "No effects"
                            ^&&^
                            (appReceiptStoreActionInputs ====
                                [._remoteReceiptRefreshResult(.success(.unit))]) <?> "Receipt refreshed"
                            ^&&^
                            (self.feedbackHandler.logs.count ==== 0)
                    },
                    
                    (systemError != nil) ==> {
                        return (nextState ==== initState) <?> "Unchanged state"
                            ^&&^
                            (effectsResults ==== [[.completed]]) <?> "No effects"
                            ^&&^
                            (appReceiptStoreActionInputs ==== []) <?> "No receipt action"
                            ^&&^
                            (self.feedbackHandler.logs.count ==== 1)
                            ^&&^
                            (self.feedbackHandler.logs[maybe: 0]?.level ==== .nonFatal(.error))
                    }
                )
        }
        
    }
    
    func testUpdatedTransactionsFinishingTransactions() {
        
        testIAPReducerUpdatedTransactions(checkerArguments: args) { initValues, result in
            
            var copy = initValues.initState
            
            let finishTxsUnrestricted = initValues.paymentTxs.enumerated()
                .map { enumerated -> (earlyExit: Bool, finishTx: Bool?) in
                    let tx = enumerated.element
                    guard let productType = initValues.env.isSupportedProduct(tx.productID()) else {
                        return (earlyExit: false, finishTx: false)
                    }
                    
                    switch tx.transactionState() {
                    case .pending(_):
                        return (earlyExit: false, finishTx: false)
                        
                    case .completed(.failure(_)):
                        return (earlyExit: false, finishTx: true)
                        
                    case .completed(.success(let completedTx)):
                        switch completedTx.completedState {
                        case .purchased, .restored:
                            switch productType {
                            case .subscription:
                                return (earlyExit: false, finishTx: true)
                                
                            case .psiCash:
                                switch copy.iap.unfinishedPsiCashTx?.transaction.isEqual(tx) {
                                case .none:
                                    copy.iap.unfinishedPsiCashTx = UnfinishedConsumableTransaction(
                                        completedTransaction: tx,
                                        verificationState: .notRequested
                                    )
                                    return (earlyExit: false, finishTx: false)
                                    
                                case .some(_):
                                    return (earlyExit: false, finishTx: false)
                                }
                            }
                        }
                    }
            }
            
            // Slices the `finishTxsUnrestricted` array at the first occurrence
            // of `earlyExit = true`
            let sliced = finishTxsUnrestricted.slice(atFirstOccurrence: { $0.earlyExit })
            let finishTxs = sliced[maybe: 0]?.filter({$0.finishTx == true}) ?? []
            
            // Assert
            return (result.paymentQueueFinishTxCalls.count ==== finishTxs.count)
        }
    }
    
    func testUpdatedTransactionsReceiptRefresh() {
        
        testIAPReducerUpdatedTransactions(checkerArguments: args) { initValues, result in
            
            let receiptRefreshedNoEarlyExit = initValues.paymentTxs.reduce(false) { prv, tx in
                switch tx.transactionState() {
                case .completed(.success(_)):
                    return prv || true
                default:
                    return prv || false
                }
            }
            
            var copy = initValues.initState
            let earlyExitCondition = initValues.paymentTxs.reduce(false) { prv, tx in
                guard let productType = initValues.env.isSupportedProduct(tx.productID()) else {
                    return prv
                }
                switch tx.transactionState() {
                case .completed(.success(let completedTx)):
                    switch completedTx.completedState {
                    case .purchased, .restored:
                        switch productType {
                        case .psiCash:
                            switch copy.iap.unfinishedPsiCashTx?.transaction.isEqual(tx) {
                            case .none:
                                copy.iap.unfinishedPsiCashTx = UnfinishedConsumableTransaction(
                                    completedTransaction: tx,
                                    verificationState: .notRequested
                                )
                                return prv
                                
                            case .some(_):
                                return prv
                            }
                        default:
                            return prv
                        }
                    }
                default:
                    return prv
                }
            }
            
            let receiptRefreshedWithEarlyExit = receiptRefreshedNoEarlyExit && !earlyExitCondition
                        
            let receiptRefreshPrivateCalls = result.appReceiptStoreCalls.filter { action in
                action == ._remoteReceiptRefreshResult(.success(.unit))
            }
            
            // Assert
            return ((receiptRefreshPrivateCalls.count > 0) ==== receiptRefreshedWithEarlyExit)
        }
    }
    
    func testUpdatedTransactionsUpdatedState() {
        
        testIAPReducerUpdatedTransactions(checkerArguments: args) { initValues, result in
            
            var expectedState = initValues.initState
            
            expectedStateLoop: for tx in initValues.paymentTxs {
                guard let productType = initValues.env.isSupportedProduct(tx.productID()) else {
                    continue expectedStateLoop
                }
                
                let updatedState: IAPPurchasing?
                
                switch tx.transactionState() {
                case .pending(_):
                    updatedState = IAPPurchasing(
                        productType: productType,
                        productID: tx.productID(),
                        purchasingState: .pending(tx.payment()))
                    
                case .completed(.failure(let error)):
                    updatedState = IAPPurchasing(
                        productType: productType,
                        productID: tx.productID(),
                        purchasingState: .completed(ErrorEvent(.storeKitError(error),
                                                               date: initValues.fixedDate))
                    )
                    
                case .completed(.success(let completedTx)):
                    switch completedTx.completedState {
                    case .purchased, .restored:
                        switch productType {
                        case .subscription:
                            updatedState = nil
                            
                        case .psiCash:
                            updatedState = nil
                            
                            switch expectedState.iap.unfinishedPsiCashTx?.transaction.isEqual(tx) {
                            
                            case .none:
                                expectedState.iap.unfinishedPsiCashTx = UnfinishedConsumableTransaction(
                                    completedTransaction: tx,
                                    verificationState: .notRequested
                                )
                                expectedState.psiCashBalance.waitingForExpectedIncrease(
                                    withAddedReward: .zero,
                                    reason: .purchasedPsiCash,
                                    persisted: MockPsiCashPersistedValues() // dummy value
                                )
                                
                            case .some(_):
                                continue expectedStateLoop
                            }
                        }
                    }
                }
                
                // Update state
                expectedState.iap.purchasing[productType] = updatedState
            }
            
            // Assert
            return (result.nextState ==== expectedState)
        }
    }
    
}

// MARK: Test Helpers

struct InitialValues {
    let initState: IAPReducerState
    let paymentTxs: [PaymentTransaction]
    let fixedDate: Date
    let env: IAPEnvironment
}

struct UpdateTxTestResult {
    let appReceiptStoreCalls: [ReceiptStateAction]
    let paymentQueueFinishTxCalls: [PaymentTransaction]
    let nextState: IAPReducerState
    let effectsResults: [[Signal<IAPAction, SignalProducer<IAPAction, Never>.SignalError>.Event]]
    let feedbackHandler: ArrayFeedbackLogHandler
}

func testIAPReducerUpdatedTransactions(
    checkerArguments: CheckerArguments?,
    _ testFunc: @escaping (InitialValues, UpdateTxTestResult) -> Testable
) {

    property("""
        IAPReducer.transactionUpdate(.updatedTransactions(_)) calls finishTransaction
        on transactions that are completed
        """, arguments: checkerArguments)
    <-
        forAll(
            IAPReducerState.arbitrary,
            TransactionUpdate.arbitraryWithOnlyUpdatedTransactionsCaseWithDuplicates
        ) { (initState: IAPReducerState, txUpdate: TransactionUpdate) in
            
            // Sanity-check
            guard case .updatedTransactions(let updatedTxs) = txUpdate else {
                XCTFatal()
            }
            
            // Arrange
            let feedbackHandler = ArrayFeedbackLogHandler()
            var env = IAPEnvironment.mock(FeedbackLogger(feedbackHandler))
            
            let fixedDate = Date()
            env.getCurrentTime = { fixedDate }
            
            var paymentQueueFinishTxsCalls = [PaymentTransaction]()
            env.paymentQueue = PaymentQueue.mock(
                transactions: nil,
                addPayment: nil,
                finishTransaction: {
                    paymentQueueFinishTxsCalls.append($0)
                    return .empty
            })
            
            var appReceiptStoreCalls = [ReceiptStateAction]()
            env.appReceiptStore = {
                appReceiptStoreCalls.append($0)
                return .empty
            }

            // Set of uniquely generated product IDs
            let uniqueProdIDs = OrderedSet(txUpdate.updatedTransactions?.map {
                $0.productID()
            } ?? [])
            
            // Last generated product is taken to be not supported in this test.
            env.isSupportedProduct = { productID -> AppStoreProductType? in
                guard let index = uniqueProdIDs.firstIndex(of: productID) else {
                    return .none
                }

                if index == uniqueProdIDs.endIndex - 1 {
                    return .none
                }
                
                return AppStoreProductIdPrefixes
                    .estimateProductTypeFromPrefix(uniqueProdIDs[index])
            }
            
            // Act
            let (nextState, effectsResults) = testReducer(initState,
                                                          .transactionUpdate(txUpdate),
                                                          env, iapReducer)
            
            return conjoin(
                
                // Empty list of updated transactions.
                (updatedTxs.count == 0) ==> {
                    return (nextState ==== initState)
                        ^&&^
                        (effectsResults ==== [])
                },
                
                // Non-empty list of updated transactions
                (updatedTxs.count > 0) ==> {
                    return testFunc(
                        InitialValues(initState: initState,
                                      paymentTxs: txUpdate.updatedTransactions!,
                                      fixedDate: fixedDate,
                                      env: env),
                        UpdateTxTestResult(appReceiptStoreCalls: appReceiptStoreCalls,
                                           paymentQueueFinishTxCalls: paymentQueueFinishTxsCalls,
                                           nextState: nextState,
                                           effectsResults: effectsResults,
                                           feedbackHandler: feedbackHandler)
                    )
                }
            )
    }
}
