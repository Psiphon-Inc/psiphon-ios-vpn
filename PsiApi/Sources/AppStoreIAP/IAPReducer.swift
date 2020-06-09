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
    case checkUnverifiedTransaction
    case purchase(product: AppStoreProduct, resultPromise: Promise<ObjCIAPResult>? = nil)
    case _purchaseAdded(AddedPayment)
    case receiptUpdated(ReceiptData?)
    case _psiCashConsumableVerificationRequestResult(
        result: RetriableTunneledHttpRequest<PsiCashValidationResponse>.RequestResult,
        forTransaction: PaymentTransaction
    )
    case transactionUpdate(TransactionUpdate)
}

/// StoreKit transaction observer
public enum TransactionUpdate: Equatable {
    case updatedTransactions([PaymentTransaction])
    case restoredCompletedTransactions(error: SystemError?)
}

extension TransactionUpdate {
    var updatedTransactions: [PaymentTransaction]? {
        guard case let .updatedTransactions(value) = self else {
            return nil
        }
        return value
    }
    
    var restoredCompletedTransactions: SystemError?? {
        guard case let .restoredCompletedTransactions(error: error) = self else {
            return nil
        }
        return .some(error)
    }
}

public struct IAPReducerState: Equatable {
    public var iap: IAPState
    public var psiCashBalance: PsiCashBalance
    public let psiCashAuth: PsiCashAuthPackage
    
    public init(iap: IAPState, psiCashBalance: PsiCashBalance, psiCashAuth: PsiCashAuthPackage) {
        self.iap = iap
        self.psiCashBalance = psiCashBalance
        self.psiCashAuth = psiCashAuth
    }
    
}

public struct IAPEnvironment {
    var feedbackLogger: FeedbackLogger
    var tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    var tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    var psiCashEffects: PsiCashEffects
    var clientMetaData: ClientMetaData
    var paymentQueue: PaymentQueue
    var isSupportedProduct: (ProductID) -> AppStoreProductType?
    var psiCashStore: (PsiCashAction) -> Effect<Never>
    var appReceiptStore: (ReceiptStateAction) -> Effect<Never>
    var httpClient: HTTPClient
    var getCurrentTime: () -> Date
    
    public init(
        feedbackLogger: FeedbackLogger,
        tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        psiCashEffects: PsiCashEffects,
        clientMetaData: ClientMetaData,
        paymentQueue: PaymentQueue,
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
        self.isSupportedProduct = isSupportedProduct
        self.psiCashStore = psiCashStore
        self.appReceiptStore = appReceiptStore
        self.httpClient = httpClient
        self.getCurrentTime = getCurrentTime
    }
}

public func iapReducer(
    state: inout IAPReducerState, action: IAPAction, environment: IAPEnvironment
) -> [Effect<IAPAction>] {
    switch action {
    case .checkUnverifiedTransaction:
        // Checks if there is an unverified transaction.
        guard state.iap.unverifiedPsiCashTx != nil else {
            return []
        }
        
        return [
            environment.appReceiptStore(.localReceiptRefresh).mapNever()
        ]
        
    case let .purchase(product: product, resultPromise: promise):
        
        // For each product type, only one product is allowed to be purchased at a time.
        guard state.iap.purchasing[product.type] == nil else {
            return []
        }
        
        if case .psiCash = product.type {
            // No action is taken if there is already an unverified PsiCash transaction.
            guard state.iap.unverifiedPsiCashTx == nil else {
                return []
            }
            
            // PsiCash IAP requires presence of PsiCash spender token.
            guard state.psiCashAuth.hasMinimalTokens else {
                
                state.iap.purchasing[product.type] = IAPPurchasing(
                    productType: product.type,
                    productID: product.productID,
                    purchasingState: .completed(
                        ErrorEvent(.failedToCreatePurchase(reason: "PsiCash data not present"),
                                   date: environment.getCurrentTime()))
                )
                
                return [
                    environment.feedbackLogger.log(
                        .error, "PsiCash IAP purchase without tokens"
                    ).mapNever()
                ]
            }
        }
        
        state.iap.purchasing[product.type] = IAPPurchasing(
            productType: product.type,
            productID: product.productID,
            purchasingState: .pending(nil),
            resultPromise: promise
        )
        
        return [
            environment.paymentQueue.addPayment(product)
                .map(IAPAction._purchaseAdded)
        ]
        
    case ._purchaseAdded(let addedPayment):
        
        let maybePendingPurchase = state.iap.purchasing[addedPayment.product.type] ?? nil
        guard maybePendingPurchase != nil else {
            environment.feedbackLogger.fatalError("""
                failed to find purchase matching payment: '\(addedPayment)'
                """)
            return []
        }
        
        // Updates purchasing state with the payment value.
        state.iap.purchasing[addedPayment.product.type] = IAPPurchasing(
            productType: addedPayment.product.type,
            productID: addedPayment.product.productID,
            purchasingState: .pending(addedPayment.payment)
        )
        
        return [
            environment.feedbackLogger.log(.info, "Added payment: '\(addedPayment)'").mapNever()
        ]
        
    case .receiptUpdated(let maybeReceiptData):
        guard let unverifiedPsiCashTx = state.iap.unverifiedPsiCashTx else {
            return []
        }
        
        // Requests verification only if one has not been made, or it failed.
        if case .pendingResponse = unverifiedPsiCashTx.verification {
            // A verification request has already been made.
            return []
        }
        
        guard let receiptData = maybeReceiptData else {
            state.iap.unverifiedPsiCashTx = UnverifiedPsiCashTransactionState(
                transaction: unverifiedPsiCashTx.transaction,
                verificationState: .requestError(
                    ErrorEvent(ErrorRepr(repr: "nil receipt"), date: environment.getCurrentTime())
                )
            )
            
            return [
                environment.feedbackLogger.log(.error, """
                    nil receipt data: \
                    failed to send verification request for transaction: \
                    '\(unverifiedPsiCashTx)'
                    """)
                    .mapNever()
            ]
        }
        
        guard let customData = environment.psiCashEffects.rewardedVideoCustomData() else {
            state.iap.unverifiedPsiCashTx = UnverifiedPsiCashTransactionState(
                transaction: unverifiedPsiCashTx.transaction,
                verificationState: .requestError(
                    ErrorEvent(
                        ErrorRepr(repr: "nil custom data"),
                        date: environment.getCurrentTime()
                    )
                )
            )
            return [
                environment.feedbackLogger.log(.error, """
                    nil customData: \
                    failed to send verification request for transaction: \
                    '\(unverifiedPsiCashTx)'
                    """)
                    .mapNever()
            ]
        }
        
        state.iap.unverifiedPsiCashTx = UnverifiedPsiCashTransactionState(
            transaction: unverifiedPsiCashTx.transaction,
            verificationState: .pendingResponse
        )
               
        // Creates request to verify PsiCash AppStore IAP purchase.

        let req = PurchaseVerifierServer.psiCash(
            requestBody: PsiCashValidationRequest(
                transaction: unverifiedPsiCashTx.transaction,
                receipt: receiptData,
                customData: customData
            ),
            clientMetaData: environment.clientMetaData
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
            psiCashVerifyRequest.callAsFunction(
                getCurrentTime: environment.getCurrentTime,
                tunnelStatusSignal: environment.tunnelStatusSignal,
                tunnelConnectionRefSignal: environment.tunnelConnectionRefSignal,
                httpClient: environment.httpClient
            ).map {
                ._psiCashConsumableVerificationRequestResult(
                    result: $0,
                    forTransaction: unverifiedPsiCashTx.transaction
                )
            },
            
            environment.feedbackLogger.log(.info, """
                Consumables in app receipt '\(receiptData.consumableInAppPurchases)'
                """).mapNever(),
            
            environment.feedbackLogger.log(.info, """
                verifying PsiCash consumable IAP with transaction ID: \
                '\(unverifiedPsiCashTx.transaction)'
                """).mapNever()
        ]
        
    case let ._psiCashConsumableVerificationRequestResult(requestResult, requestTransaction):
        guard let unverifiedPsiCashTx = state.iap.unverifiedPsiCashTx else {
            environment.feedbackLogger.fatalError("expected non-nil 'unverifiedPsiCashTx'")
            return []
        }
        
        guard case .pendingResponse = unverifiedPsiCashTx.verification else {
            environment.feedbackLogger.fatalError("""
                unexpected state for unverified PsiCash IAP transaction \
                '\(String(describing: state.iap.unverifiedPsiCashTx))'
                """)
            return []
        }
        
        guard unverifiedPsiCashTx.transaction == requestTransaction else {
            environment.feedbackLogger.fatalError("""
                expected transactions to be equal: \
                '\(String(describing: requestTransaction.transactionID()))' != \
                '\(String(describing: unverifiedPsiCashTx.transaction.transactionID()))'
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
        
        case .failed(let errorEvent):
            // Authorization request finished in failure, and will not be retried automatically.
            
            state.iap.unverifiedPsiCashTx = UnverifiedPsiCashTransactionState(
                transaction: requestTransaction,
                verificationState: .requestError(errorEvent.eraseToRepr())
            )
            
            return [
                environment.feedbackLogger.log(.error, """
                    verification request failed: '\(errorEvent)'\
                    transaction: '\(requestTransaction)'
                    """).mapNever()
            ]
        
        case .completed(let psiCashValidationResponse):
            switch psiCashValidationResponse {
            case .success(.unit):
                // 200-OK response from the server
                state.iap.unverifiedPsiCashTx = .none
                
                // Finishes the transaction, and refreshes PsiCash state for the latest balance.
                return [
                    environment.paymentQueue.finishTransaction(requestTransaction).mapNever(),
                    environment.psiCashStore(.refreshPsiCashState).mapNever(),
                    environment.feedbackLogger.log(.info, "verified consumable transaction: '\(requestTransaction)'")
                        .mapNever()
                ]
            
            case .failure(let errorEvent):
                // Non-200 OK response.
                
                // This is a fatal error and should not happen in production.
                state.iap.unverifiedPsiCashTx = UnverifiedPsiCashTransactionState(
                    transaction: requestTransaction,
                    verificationState: .requestError(errorEvent.eraseToRepr())
                )
                
                return [
                    environment.feedbackLogger.log(.error, """
                        verification failed: '\(errorEvent)'\
                        transaction: '\(requestTransaction)'
                        """).mapNever()
                ]
            }
        }
        
    case .transactionUpdate(let value):
        switch value {
        case .restoredCompletedTransactions(error: let maybeError):
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

            
        case .updatedTransactions(let transactions):
            var effects = [Effect<IAPAction>]()
            
            for tx in transactions {
                
                guard let productType = environment.isSupportedProduct(tx.productID()) else {
                    // Transactions with unknown product ID should not happen in production,
                    // and hence `finishTransaction(_:)` is not called on them.
                    effects.append(
                        environment.feedbackLogger.log(.error,
                                                       "unknown product id '\(tx.productID())'")
                            .mapNever()
                    )
                    
                    continue
                }
                
                switch tx.transactionState() {
                case .pending(_):
                    continue
                    
                case .completed(let completedState):
                    
                    let finishTransaction: Bool
                    let updatedPurchasingState: IAPPurchasing?
                    
                    switch completedState {
                        
                    case let .failure(skError):
                        updatedPurchasingState = IAPPurchasing(
                            productType: productType,
                            productID: tx.productID(),
                            purchasingState: .completed(
                                ErrorEvent(.storeKitError(skError),
                                           date: environment.getCurrentTime())
                            )
                        )
                        
                        finishTransaction = true
                        
                    case let .success(success):
                        updatedPurchasingState = nil
                        
                        switch success.second {
                            
                        case .restored :
                            finishTransaction = true
                            
                        case .purchased:
                            switch productType {
                                
                            case .subscription:
                                finishTransaction = true
                                
                            case .psiCash:
                                finishTransaction = false
                                
                                switch state.iap.unverifiedPsiCashTx?.transaction
                                    .isEqualTransactionID(to: tx)
                                {
                                case .none:
                                    // There is no unverified psicash IAP transaction.
                                                                            
                                    state.iap.unverifiedPsiCashTx =
                                        UnverifiedPsiCashTransactionState(
                                            transaction: tx,
                                            verificationState: .notRequested
                                    )
                                    
                                    effects.append(
                                        environment.feedbackLogger.log(.info, """
                                            New PsiCash consumable transaction '\(tx)'
                                            """).mapNever()
                                    )
                                    
                                case .some(true):
                                    // Transaction has the same identifier as the current
                                    // unverified psicash IAP transaction.
                                    effects.append(
                                        environment.feedbackLogger.log(.warn,"""
                                            unexpected duplicate transaction with id \
                                            '\(tx.transactionID())'
                                            """).mapNever()
                                    )
                                    continue
                                    
                                case .some(false):
                                    // Unexpected presence of two consumable transactions
                                    // with different transaction ids.
                                    environment.feedbackLogger.fatalError("""
                                        found two completed but unverified consumable purchases: \
                                        unverified transaction: \
                                        '\(String(describing:
                                        state.iap.unverifiedPsiCashTx?.transaction.transactionID)
                                        )', \
                                        new transaction: \
                                        '\(tx.transactionID())'
                                        """)
                                    return []
                                }

                            }
                        }
                    }
                    

                    // Fulfills pending purchase promise for product referred
                    // to by the current transaction.
                    if let product = state.iap.purchasing[productType] ?? nil {
                        let error = updatedPurchasingState?.purchasingState.completed
                        product.resultPromise?.fulfill(
                            ObjCIAPResult(transaction: tx.skPaymentTransaction()!,
                                          error: error)
                        )
                    }
                    
                    // Updates purchasing state
                    state.iap.purchasing[productType] = updatedPurchasingState
                    
                    if finishTransaction {
                        effects.append(
                            environment.paymentQueue.finishTransaction(tx).mapNever()
                        )
                    }
                }
            }
            
            if transactions.map({$0.transactionState().appReceiptUpdated}).contains(true) {
                effects.append(
                    environment.appReceiptStore(
                        ._remoteReceiptRefreshResult(.success(.unit))).mapNever()
                )
            }
            
            return effects
        }
    }
}
