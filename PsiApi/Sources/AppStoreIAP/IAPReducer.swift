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
import Promises
import StoreKit
import Utilities
import PsiApi
import PsiCashClient

public enum IAPAction: Equatable {
    case retryUnverifiedTransaction
    case purchase(product: AppStoreProduct, resultPromise: Promise<ObjCIAPResult>? = nil)
    case appReceiptDataUpdated(ReceiptData?)
    case _psiCashConsumableVerificationRequestResult(
            result: RetriableTunneledHttpRequest<PsiCashValidationResponse>.RequestResult,
            forTransaction: AppStorePaymentTransaction)
    case appStoreTransactionUpdate(TransactionUpdate)
}

/// StoreKit transaction observer values.
/// Represents callbacks received from `SKPaymentTransactionObserver` of `SKPaymentQueue` object.
public enum TransactionUpdate: Equatable {
    
    /// Transaction array has changed (additions or state changes).
    case updatedTransactions([AppStorePaymentTransaction])
    
    /// Represents result of `SKPaymentQueue` restoring transactions.
    /// Ending in either success `.none` or failure `SystemError<Int>`.
    case restoredCompletedTransactions(maybeError: SystemError<Int>?)
    
}

extension TransactionUpdate {
    var updatedTransactions: [AppStorePaymentTransaction]? {
        guard case let .updatedTransactions(value) = self else {
            return nil
        }
        return value
    }
    
    var restoredCompletedTransactions: SystemError<Int>?? {
        guard case let .restoredCompletedTransactions(maybeError: error) = self else {
            return nil
        }
        return .some(error)
    }
}

public struct IAPReducerState: Equatable {
    
    public var iap: IAPState
    public var psiCashBalance: PsiCashBalance
    public let receiptData: ReceiptData??
    public let psiCashAccountType: PsiCashAccountType?
    
    public init(
        iap: IAPState,
        psiCashBalance: PsiCashBalance,
        receiptData: ReceiptData??,
        psiCashAccountType: PsiCashAccountType?
    ) {
        self.iap = iap
        self.psiCashBalance = psiCashBalance
        self.receiptData = receiptData
        self.psiCashAccountType = psiCashAccountType
    }
    
}

public struct IAPEnvironment {
    var feedbackLogger: FeedbackLogger
    var tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    var tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    var psiCashEffects: PsiCashEffectsProtocol
    var clientMetaData: () -> ClientMetaData
    var paymentQueue: AppStorePaymentQueue
    var psiCashPersistedValues: PsiCashPersistedValues
    var isSupportedProduct: (ProductID) -> AppStoreProductType?
    var psiCashStore: (PsiCashAction) -> Effect<Never>
    var appReceiptStore: (ReceiptStateAction) -> Effect<Never>
    var httpClient: HTTPClient
    var getCurrentTime: () -> Date
    
    public init(
        feedbackLogger: FeedbackLogger,
        tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        psiCashEffects: PsiCashEffectsProtocol,
        clientMetaData: @escaping () -> ClientMetaData,
        paymentQueue: AppStorePaymentQueue,
        psiCashPersistedValues: PsiCashPersistedValues,
        isSupportedProduct: @escaping (ProductID) -> AppStoreProductType?,
        psiCashStore: @escaping (PsiCashAction) -> Effect<Never>,
        appReceiptStore: @escaping (ReceiptStateAction) -> Effect<Never>,
        httpClient: HTTPClient,
        getCurrentTime: @escaping () -> Date
    ) {
        self.feedbackLogger = feedbackLogger
        self.tunnelStatusSignal = tunnelStatusSignal
        self.tunnelConnectionRefSignal = tunnelConnectionRefSignal
        self.psiCashEffects = psiCashEffects
        self.clientMetaData = clientMetaData
        self.paymentQueue = paymentQueue
        self.psiCashPersistedValues = psiCashPersistedValues
        self.isSupportedProduct = isSupportedProduct
        self.psiCashStore = psiCashStore
        self.appReceiptStore = appReceiptStore
        self.httpClient = httpClient
        self.getCurrentTime = getCurrentTime
    }
}

public let iapReducer = Reducer<IAPReducerState, IAPAction, IAPEnvironment> {
    state, action, environment in
    
    switch action {
        
    case .retryUnverifiedTransaction:
        
        // Checks if there is an unverified transaction.
        // TODO: Limited to PsiCash purchases only.
        guard
            case .completed(.success(let unfinishedPsiCashTx)) = state.iap.purchasing[.psiCash],
            unfinishedPsiCashTx.verificationStatus != .pendingResponse
        else {
            return []
        }
        
        // state.receiptData is `.none` if the receipt file has never been read by the app.
        guard let readReceipt = state.receiptData else {
            return []
        }
        
        return [
            Effect(value: .appReceiptDataUpdated(readReceipt))
        ]
        
    case let .purchase(product: product, resultPromise: maybeObjcSubscriptionPromise):
        
        switch state.iap.purchasing[product.type] {
        case .pending(_), .completed(.success(_)):
            
            // Pending purchase or verification.
            return [
                environment.feedbackLogger.log(.warn, """
                        Purchase pending: unverified PsiCash transaction: \
                        '\(makeFeedbackEntry(state.iap.purchasing[product.type]))'
                        """).mapNever()
            ]
            
        case nil, .completed(.failure(_)):
            // No purchase, or last purchase finished successfully or failed.
            break
        }
        
        switch product.type {
        case .psiCash:
            
            // PsiCash IAP requires presence of PsiCash spender token.
            guard state.psiCashAccountType != .noTokens else {
                
                let errorEvent = ErrorEvent(
                    IAPState.IAPError.failedToCreatePurchase(reason: "PsiCash data not present"),
                    date: environment.getCurrentTime()
                )
                
                state.iap.purchasing[product.type] = .completed(.failure(errorEvent))
                
                return [
                    environment.feedbackLogger.log(
                        .error, "PsiCash IAP purchase without tokens"
                    ).mapNever()
                ]
            }
            
        case .subscription:
            if let promise = maybeObjcSubscriptionPromise {
                state.iap.objcSubscriptionPromises.append(promise)
            }
        }
        
        // Sets App Store purchase state for the given product to pending.
        state.iap.purchasing[product.type] = .pending(.purchasing)
        
        return [
            environment.paymentQueue.addPayment(product).mapNever(),
            environment.feedbackLogger.log(
                .info, "request to purchase: '\(makeFeedbackEntry(product))'").mapNever()
        ]
        
    case .appReceiptDataUpdated(let maybeReceiptData):
        
        // If there are is an unfinished consumable transaction announced by the default
        // `SKPaymentQueue`, then is it checked against the local app receipt (which is
        // assumed to contain this unfinished transaction).
        //
        // Note that `finishTransaction(_:)` is called immediately after a new
        // subscription transaction is observed. Whereas the PsiCash consumable
        // transactions are first submitted to the purchase-verifier server,
        // where the user's account gets credited, and `finishTransaction(_:)`
        // is only called after a 200 OK response.
        
        guard
            case .completed(.success(let unfinishedPsiCashTx)) = state.iap.purchasing[.psiCash]
        else {
            return [
                environment.feedbackLogger
                    .log(.info, """
                        appReceiptDataUpdated but not unfinished PsiCash transactionx observed
                        """).mapNever()
            ]
        }
        
        // Guards against sending the same request twice.
        guard unfinishedPsiCashTx.verificationStatus != .pendingResponse else {
            return []
        }
        
        guard let receiptData = maybeReceiptData else {
            
            state.iap.purchasing[.psiCash] =
                .completed(
                    .success(
                        UnifinishedTransaction(
                            transaction: unfinishedPsiCashTx.transaction,
                            verificationStatus: .requestError(
                                ErrorEvent(
                                    ErrorRepr(repr: "nil receipt"),
                                    date: environment.getCurrentTime())
                                ))))
            
            return [
                environment.feedbackLogger.log(.error, """
                    nil receipt data: \
                    failed to send verification request for transaction: \
                    '\(unfinishedPsiCashTx)'
                    """)
                .mapNever()
            ]
        }
        
        // Finds matching transaction in the receipt file.
        // We expect to find only one such transaction in the receipt.
        let purchaseInReceiptMaybe = receiptData.consumableInAppPurchases.filter {
            $0.matches(paymentTransaction: unfinishedPsiCashTx.transaction)
        }
        
        guard let consumableIAP = purchaseInReceiptMaybe.singletonElement else {
            environment.feedbackLogger.fatalError("Matched more than one transaction in the receipt. \(purchaseInReceiptMaybe)")
            return []
        }
        
        guard let customData = environment.psiCashEffects.rewardedVideoCustomData() else {
            
            state.iap.purchasing[.psiCash] =
                .completed(
                    .success(
                        UnifinishedTransaction(
                            transaction: unfinishedPsiCashTx.transaction,
                            verificationStatus: .requestError(
                                ErrorEvent(
                                    ErrorRepr(repr: "nil custom data"),
                                    date: environment.getCurrentTime()
                                )))))
            
            return [
                environment.feedbackLogger.log(.error, """
                    nil customData: \
                    failed to send verification request for transaction: \
                    '\(unfinishedPsiCashTx)'
                    """)
                .mapNever()
            ]
        }
        
        state.iap.purchasing[.psiCash] =
            .completed(
                .success(
                    UnifinishedTransaction(
                        transaction: unfinishedPsiCashTx.transaction,
                        verificationStatus: .pendingResponse)))
        
        // Creates request to verify PsiCash AppStore IAP purchase.
        
        let req = PurchaseVerifierServer.psiCash(
            requestBody: PsiCashValidationRequest(
                productID: unfinishedPsiCashTx.transaction.productID(),
                transactionID: consumableIAP.transactionID,
                receipt: receiptData,
                customData: customData
            ),
            clientMetaData: environment.clientMetaData()
        )
        
        let psiCashVerifyRequest = RetriableTunneledHttpRequest(
            request: req.request
        )
        
        var effects = [Effect<IAPAction>]()
        
        if let error = req.error {
            effects += [environment.feedbackLogger.log(.error,
                                                       tag: "IAPReducer.receiptUpdated",
                                                       error).mapNever()]
        }
        
        return effects + [
            psiCashVerifyRequest(
                getCurrentTime: environment.getCurrentTime,
                tunnelStatusSignal: environment.tunnelStatusSignal,
                tunnelConnectionRefSignal: environment.tunnelConnectionRefSignal,
                httpClient: environment.httpClient
            ).map {
                ._psiCashConsumableVerificationRequestResult(
                    result: $0,
                    forTransaction: unfinishedPsiCashTx.transaction
                )
            },
            
            environment.feedbackLogger.log(.info, """
                Consumables in app receipt '\(receiptData.consumableInAppPurchases)'
                """).mapNever(),
            
            environment.feedbackLogger.log(.info, """
                verifying PsiCash consumable IAP with transaction: '\(unfinishedPsiCashTx)'
                """).mapNever()
        ]
        
    case let ._psiCashConsumableVerificationRequestResult(requestResult, requestTransaction):
        
        guard
            case .completed(.success(let unfinishedPsiCashTx)) = state.iap.purchasing[.psiCash],
            case .pendingResponse = unfinishedPsiCashTx.verificationStatus
        else {
            environment.feedbackLogger.fatalError(
                "Expected UnifinishedTransaction with pendingResponse value")
            return []
        }
        
        guard unfinishedPsiCashTx.transaction == requestTransaction else {
            environment.feedbackLogger.fatalError("""
                expected transactions to be equal: \
                '\(makeFeedbackEntry(requestTransaction))' != \
                '\(makeFeedbackEntry(unfinishedPsiCashTx.transaction))'
                """)
            return []
        }
        
        switch requestResult {
        
        case .willRetry(when: let retryCondition):
            // Authorization request will be retried whenever retryCondition becomes true.
            switch retryCondition {
            case .whenResolved(tunnelError: .nilTunnelProviderManager):
                return [ environment.feedbackLogger.log(.error, retryCondition).mapNever() ]
                
            case .whenResolved(tunnelError: .tunnelNotConnected):
                // This event is too frequent to log.
                return []
                
            case .afterTimeInterval:
                return [ environment.feedbackLogger.log(.error, retryCondition).mapNever() ]
            }
            
        case .completed(let psiCashValidationResponse):
            switch psiCashValidationResponse {
            case .success(.unit):
                // 200-OK response from the server
                state.iap.purchasing[.psiCash] = nil
                
                // Finishes the transaction, and refreshes PsiCash state for the latest balance.
                return [
                    environment.paymentQueue.finishTransaction(requestTransaction).mapNever(),
                    environment.psiCashStore(.refreshPsiCashState()).mapNever(),
                    environment.feedbackLogger.log(.info, "verified consumable transaction: '\(requestTransaction)'")
                    .mapNever()
                ]
                
            case .failure(let errorEvent):
                // Request failed or received a non-200 OK response.
                
                state.iap.purchasing[.psiCash] =
                    .completed(
                        .success(
                            UnifinishedTransaction(
                                transaction: unfinishedPsiCashTx.transaction,
                                verificationStatus: .requestError(errorEvent.eraseToRepr()))))

                
                var effects = [Effect<IAPAction>]()
                
                // PsiCash RefreshState is most likely needed if a 4xx status code
                // is returned from the purchase-verifier server. E.g. user's token's
                // might have been expired.
                if
                    case .errorStatusCode(let responseMetadata) = errorEvent.error,
                    case .clientError = responseMetadata.statusCode.responseType
                {
                    
                    effects += environment.psiCashStore(.refreshPsiCashState())
                        .mapNever()
                    
                }
                
                effects += environment.feedbackLogger.log(.error, """
                        verification failed: '\(errorEvent)'\
                        transaction: '\(requestTransaction)'
                        """).mapNever()
                
                return effects
            }
        }
        
    case .appStoreTransactionUpdate(.restoredCompletedTransactions(maybeError: let maybeError)):
        if let error = maybeError {
            return [
                environment.feedbackLogger.log(
                    .error, "restore completed transactions failed: '\(error)'").mapNever()
            ]
        } else {
            return [
                environment.appReceiptStore(._remoteReceiptRefreshResult(.success(.unit)))
                .mapNever()
            ]
        }
        
    case .appStoreTransactionUpdate(.updatedTransactions(let updatedTransactions)):
        
        var effects = [Effect<IAPAction>]()
        
        for tx: AppStorePaymentTransaction in updatedTransactions {
            
            guard
                let productType: AppStoreProductType = environment.isSupportedProduct(tx.productID())
            else {
                // Transactions with unknown product ID should not happen in production,
                // and hence `finishTransaction(_:)` is not called on them.
                effects += environment.feedbackLogger
                    .log(.error, "unknown product id '\(tx.productID())'") .mapNever()
                
                continue
            }
            
            effects +=
                environment.feedbackLogger.log(
                    .info, "transactionUpdate: '\(makeFeedbackEntry(tx))'").mapNever()
            
            // Switches over PaymentTransaction transaction state.
            switch tx.transactionState() {
            case .pending(let isDeferred):
                // SKPaymentTransaction state: `purchasing` or `deferred`.
                
                state.iap.purchasing[productType] = .pending(isDeferred)
                
            case .completed(.success(let completedTransaction)):
                // SKPaymentTransaction state: `purchased` or `restored`.
                
                switch productType {
                case .subscription:
                    
                    // Removes purchaes from stat.
                    state.iap.purchasing[.subscription] = nil
                    
                    // Subscription products are finished immediately and verified later.
                    // TODO: Finish Subscription transactions only after the purchase is verified.
                    effects += environment.paymentQueue.finishTransaction(tx).mapNever()

                case .psiCash:
                    
                    switch state.iap.purchasing[.psiCash] {
                    case nil, .pending(_), .completed(.failure(_)):
                        
                        state.iap.purchasing[productType] =
                            .completed(.success(
                                UnifinishedTransaction(
                                    transaction: tx,
                                    verificationStatus: .notRequested
                                )))
                        
                        // Updates psiCashBalance state to indicate expectation
                        // in balance increase.
                        state.psiCashBalance.waitingForExpectedIncrease(
                            withAddedReward: .zero,
                            reason: .purchasedPsiCash,
                            persisted: environment.psiCashPersistedValues
                        )
                        
                        effects += environment.feedbackLogger.log(.info, """
                                new IAP transaction: '\(makeFeedbackEntry(tx))'
                                """)
                        .mapNever()
                        
                    case .completed(.success(let unfinishedPsiCashTx)):
                        // An unfinished PsiCash IAP transaction is already observed. Logs it.
                        
                        if unfinishedPsiCashTx.transaction.completedTransaction == completedTransaction {
                            // There is already an existing unfinished consumable transaction.
                            effects += environment.feedbackLogger.log(.warn, """
                                Transaction is a duplicate: '\(makeFeedbackEntry(tx))'
                                """).mapNever()
                        } else {
                            // Duplicate transaction with a different identifier.
                            // This is unexpected.
                            environment.feedbackLogger.fatalError(
                                "Transaction duplicate with different paymentTransactionId")
                            return []
                        }
                        
                    }
                    
                }
                
            case .completed(.failure(let appStoreError)):
                // SKPaymentTransaction state: `failed` or some other error.
                
                let errorEvent = ErrorEvent(
                    IAPState.IAPError.storeKitError(appStoreError),
                    date: environment.getCurrentTime()
                )
                
                state.iap.purchasing[productType] = .completed(.failure(errorEvent))
                
                // Transaction failed, removes it from the payment queue.
                effects += environment.paymentQueue.finishTransaction(tx).mapNever()

                effects += environment.feedbackLogger.log(.info, """
                    failed IAP transaction: '\(makeFeedbackEntry(tx))'
                    """)
                .mapNever()
            }
            
            // Fulfills all pending subscription purchase promises (if any)
            // if the current transaction `tx` is a completed subscription transaction.
            // Note: `state.iap.purchasing[productType]` should be updated
            //        before the objcPromise is resolved.
            if
               case .completed(_) = tx.transactionState(),
               case .subscription = productType
            {
                
                let maybeError = state.iap.purchasing[productType]?.completedToOptional?.failureToOptional()
                
                if state.iap.objcSubscriptionPromises.count > 0 {
                    fulfillAll(promises: state.iap.objcSubscriptionPromises,
                               with: ObjCIAPResult(transaction: tx.skPaymentTransaction()!,
                                                   error: maybeError))

                    state.iap.objcSubscriptionPromises = []
                }

            }

        } // end for
        
        // Signals `environment.appReceiptStore` that the App Store receipt is potentially
        // updated if any of the transactions has completed successfully.
        if updatedTransactions.map({$0.transactionState().isReceiptUpdated}).contains(true) {

            effects += environment
                .appReceiptStore(._remoteReceiptRefreshResult(.success(.unit)))
                .mapNever()

        }
        
        return effects
    }
}
