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

enum IAPAction {
    case checkUnverifiedTransaction
    case purchase(IAPPurchasableProduct)
    case purchaseAdded(PurchaseAddedResult)
    case _psiCashConsumableAuthorizationRequestResult(
        result: RetriableTunneledHttpRequest<PsiCashValidationResponse>.RequestResult,
        forTransaction: PaymentTransaction
    )
    case transactionUpdate(TransactionUpdate)
    case receiptUpdated(ReceiptData?)
}

/// StoreKit transaction observer
enum TransactionUpdate {
    case updatedTransactions([PaymentTransaction])
    case restoredCompletedTransactions(error: Error?)
}

struct IAPReducerState<T: TunnelProviderManager> {
    var iap: IAPState
    var psiCashBalance: PsiCashBalance
    let psiCashAuth: PsiCashAuthPackage
}

typealias IAPEnvironment = (
    tunnelStatusWithIntentSignal: SignalProducer<VPNStatusWithIntent, Never>,
    tunnelManagerRefSignal: SignalProducer<WeakRef<PsiphonTPM>?, Never>,
    psiCashEffects: PsiCashEffect,
    clientMetaData: ClientMetaData,
    paymentQueue: PaymentQueue,
    userConfigs: UserDefaultsConfig,
    psiCashStore: (PsiCashAction) -> Effect<Never>,
    appReceiptStore: (ReceiptStateAction) -> Effect<Never>
)

func iapReducer<T: TunnelProviderManager>(
    state: inout IAPReducerState<T>, action: IAPAction, environment: IAPEnvironment
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
        
    case .purchase(let product):
        guard state.iap.purchasing.completed else {
            return []
        }
        
        if case .psiCash = product {
            // No action is taken if there is already an unverified PsiCash transaction.
            guard state.iap.unverifiedPsiCashTx == nil else {
                return []
            }
            
            // PsiCash IAP requires presence of PsiCash spender token.
            guard state.psiCashAuth.hasMinimalTokens else {
                state.iap.purchasing = .error(ErrorEvent(
                    .failedToCreatePurchase(reason: "PsiCash data not present.")
                ))
                return []
            }
        }
    
        state.iap.purchasing = .pending(product)

        return [
            environment.paymentQueue.addPurchase(product)
                .map(IAPAction.purchaseAdded)
        ]
        
    case .purchaseAdded(let result):
        switch result {
        case .success(_):
            return []
            
        case .failure(let errorEvent):
            state.iap.purchasing = .error(errorEvent)
            return []
        }
        
    case .receiptUpdated(let maybeReceiptData):
        guard let unverifiedPsiCashTx = state.iap.unverifiedPsiCashTx else {
            return []
        }
        
        // Requests verification only if one has not been made, or it failed.
        if case .pendingVerificationResult = unverifiedPsiCashTx.verificationState {
            // A verification request has already been made.
            return []
        }
        
        guard let receiptData = maybeReceiptData else {
            state.iap.unverifiedPsiCashTx = UnverifiedPsiCashTransactionState(
                transaction: unverifiedPsiCashTx.transaction,
                verificationState: .requestError(
                    ErrorEvent(ErrorRepr(repr: "nil receipt"))
                )
            )
            return [
                feedbackLog(.error, """
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
                    ErrorEvent(ErrorRepr(repr: "nil custom data"))
                )
            )
            return [
                feedbackLog(.error, """
                    nil customData: \
                    failed to send verification request for transaction: \
                    '\(unverifiedPsiCashTx)'
                    """)
                    .mapNever()
            ]
        }
        
        state.iap.unverifiedPsiCashTx = UnverifiedPsiCashTransactionState(
            transaction: unverifiedPsiCashTx.transaction,
            verificationState: .pendingVerificationResult
        )
               
        let authRequest = RetriableTunneledHttpRequest(
            request: PurchaseVerifierServerEndpoints.psiCash(
                requestBody: PsiCashValidationRequest(
                    transaction: unverifiedPsiCashTx.transaction,
                    receipt: receiptData,
                    customData: customData
                ),
                clientMetaData: environment.clientMetaData
            )
        )
        
        return [
            authRequest.callAsFunction(
                tunnelStatusWithIntentSignal: environment.tunnelStatusWithIntentSignal,
                tunnelManagerRefSignal: environment.tunnelManagerRefSignal
            ).map {
                ._psiCashConsumableAuthorizationRequestResult(
                    result: $0,
                    forTransaction: unverifiedPsiCashTx.transaction
                )
            },
            
            feedbackLog(.info, """
                Consumables in app receipt '\(receiptData.consumableInAppPurchases)'
                """).mapNever(),
            
            feedbackLog(.info, """
                verifying PsiCash consumable IAP with transaction ID: \
                '\(unverifiedPsiCashTx.transaction)'
                """).mapNever()
        ]
        
    case let ._psiCashConsumableAuthorizationRequestResult(requestResult, requestTransaction):
        guard let unverifiedPsiCashTx = state.iap.unverifiedPsiCashTx else {
            fatalErrorFeedbackLog("expected non-nil 'unverifiedPsiCashTx'")
        }
        
        guard case .pendingVerificationResult = unverifiedPsiCashTx.verificationState else {
            fatalErrorFeedbackLog("""
                unexpected state for unverified PsiCash IAP transaction \
                '\(String(describing: state.iap.unverifiedPsiCashTx))'
                """)
        }
        
        guard unverifiedPsiCashTx.transaction == requestTransaction else {
            fatalErrorFeedbackLog("""
                expected transactions to be equal: \
                '\(String(describing: requestTransaction.transactionID()))' != \
                '\(String(describing: unverifiedPsiCashTx.transaction.transactionID()))'
                """)
        }
        
        switch requestResult {
            
        case .willRetry(when: let retryCondition):
            // Authorization request will be retried whenever retryCondition becomes true.
            switch retryCondition {
            case .whenResolved(tunnelError: .nilTunnelProviderManager):
                return [ feedbackLog(.error, retryCondition).mapNever() ]
                
            case .whenResolved(tunnelError: .tunnelNotConnected):
                // This event is too frequent to log.
                return []

            case .afterTimeInterval:
                return [ feedbackLog(.error, retryCondition).mapNever() ]
            }
        
        case .failed(let errorEvent):
            // Authorization request finished in failure, and will not be retried automatically.
            
            state.iap.unverifiedPsiCashTx = UnverifiedPsiCashTransactionState(
                transaction: requestTransaction,
                verificationState: .requestError(errorEvent.eraseToRepr())
            )
            
            return [
                feedbackLog(.error, """
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
                    feedbackLog(.info, "verified consumable transaction: '\(requestTransaction)'")
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
                    feedbackLog(.error, """
                        verification failed: '\(errorEvent)'\
                        transaction: '\(requestTransaction)'
                        """).mapNever()
                ]
            }
        }
        
    case .transactionUpdate(let value):
        switch value {
        case .restoredCompletedTransactions:
            return [
                environment.appReceiptStore(._remoteReceiptRefreshResult(.success(()))).mapNever()
            ]
            
        case .updatedTransactions(let transactions):
            var effects = [Effect<IAPAction>]()
            
            for transaction in transactions {
                switch transaction.transactionState() {
                case .pending(_):
                    return []
                    
                case .completed(let completedState):
                    let finishTransaction: Bool
                    let purchasingState: IAPPurchasingState
                    
                    switch completedState {
                    case let .failure(skError):
                        purchasingState = .error(ErrorEvent(.storeKitError(skError)))
                        finishTransaction = true
                        
                    case let .success(success):
                        purchasingState = .none
                        switch success {
                        case .purchased:
                            switch try? AppStoreProductType.from(transaction: transaction) {
                            case .none:
                                fatalErrorFeedbackLog(
                                    "unknown product \(String(describing: transaction))"
                                )
                                
                            case .psiCash:
                                switch state.iap.unverifiedPsiCashTx?.transaction
                                    .isEqualTransactionID(to:transaction)
                                {
                                case .none:
                                    // There is no unverified psicash IAP transaction.
                                        
                                    finishTransaction = false
                                    
                                    state.iap.unverifiedPsiCashTx =
                                        UnverifiedPsiCashTransactionState(
                                            transaction: transaction,
                                            verificationState: .notRequested
                                        )
                                    
                                    effects.append(
                                        feedbackLog(.info, """
                                            New PsiCash consumable transaction '\(transaction)'
                                            """).mapNever()
                                    )
                                    
                                    // Performs a local receipt refresh before submitting
                                    // the receipt for verification.
                                    effects.append(
                                        environment.appReceiptStore(.localReceiptRefresh).mapNever()
                                    )
                                    
                                case .some(true):
                                    // Transaction has the same identifier as the current
                                    // unverified psicash IAP transaction.
                                    finishTransaction = true
                                    
                                case .some(false):
                                    // Unexpected presence of two consumable transactions
                                    // with different transaction ids.
                                    fatalErrorFeedbackLog("""
                                        found two completed but unverified consumable purchases: \
                                        unverified transaction: \
                                        '\(String(describing:
                                        state.iap.unverifiedPsiCashTx?.transaction.transactionID)
                                        )', \
                                        new transaction: \
                                        '\(transaction.transactionID())'
                                        """)
                                }

                            case .subscription:
                                finishTransaction = true
                            }
                            
                        case .restored :
                            finishTransaction = true
                        }
                    }
                    
                    // Updates purchasing state
                    state.iap.purchasing = purchasingState
                    
                    if finishTransaction {
                        effects.append(
                            environment.paymentQueue.finishTransaction(transaction).mapNever()
                        )
                    }
                    
                    if transactions.map({ $0.transactionState().appReceiptUpdated }).contains(true) {
                        effects.append(
                            environment.appReceiptStore(._remoteReceiptRefreshResult(.success(()))).mapNever()
                        )
                    }
                }
            }
            
            return effects
        }
    }
}

/// Delegate for StoreKit transactions.
/// - Note: There is no callback from StoreKit if purchasing a product that is already
/// purchased.
final class PaymentTransactionDelegate: StoreDelegate<TransactionUpdate>,
SKPaymentTransactionObserver {
    
    // Sent when transactions are removed from the queue (via finishTransaction:).
    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions
        transactions: [SKPaymentTransaction]) {
        // Ignore.
    }
    
    // Sent when an error is encountered while adding transactions
    // from the user's purchase history back to the queue.
    func paymentQueue(_ queue: SKPaymentQueue,
                      restoreCompletedTransactionsFailedWithError error: Error) {
        storeSend(.restoredCompletedTransactions(error: error))
    }
    
    // Sent when all transactions from the user's purchase history have
    // successfully been added back to the queue.
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        storeSend(.restoredCompletedTransactions(error: .none))
    }
    
    // Sent when a user initiates an IAP buy from the App Store
    @available(iOS 11.0, *)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment,
                      for product: SKProduct) -> Bool {
        return false
    }
    
    // Sent when the transaction array has changed (additions or state changes).
    // Client should check state of transactions and finish as appropriate.
    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        storeSend(
            .updatedTransactions(transactions.map(PaymentTransaction.make(from:)))
        )
    }
    
    @available(iOS 13.0, *)
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        // Do nothing.
    }
    
}
