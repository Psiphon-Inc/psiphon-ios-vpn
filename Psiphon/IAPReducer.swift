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
    case purchase(IAPPurchasableProduct)
    case purchaseAdded(PurchaseAddedResult)
    case verifiedPsiCashConsumable(VerifiedPsiCashConsumableTransaction)
    case transactionUpdate(TransactionUpdate)
    case receiptUpdated(ReceiptData?)
}

/// StoreKit transaction observer
enum TransactionUpdate {
    case updatedTransactions([SKPaymentTransaction])
    case restoredCompletedTransactions(error: Error?)
}

struct IAPReducerState {
    var iap: IAPState
    var psiCashBalance: PsiCashBalance
    let psiCashAuth: PsiCashAuthPackage
}

typealias IAPEnvironment = (
    tunnelStatusWithIntentSignal: SignalProducer<VPNStatusWithIntent, Never>,
    psiCashEffects: PsiCashEffect,
    clientMetaData: ClientMetaData,
    paymentQueue: PaymentQueue,
    userConfigs: UserDefaultsConfig,
    psiCashStore: (PsiCashAction) -> Effect<Never>,
    appReceiptStore: (ReceiptStateAction) -> Effect<Never>
)

func iapReducer(
    state: inout IAPReducerState, action: IAPAction, environment: IAPEnvironment
) -> [Effect<IAPAction>] {
    switch action {
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
        guard let receiptData = maybeReceiptData else {
            return []
        }
        guard case let .pendingVerification(unverifiedTx) = state.iap.unverifiedPsiCashTx else {
            return []
        }
        state.iap.unverifiedPsiCashTx = .pendingVerificationResult(unverifiedTx)
        return [
            verifyConsumable(transaction: unverifiedTx,
                             receipt: receiptData,
                             tunnelProviderStatusSignal: environment.tunnelStatusWithIntentSignal,
                             psiCashEffects: environment.psiCashEffects,
                             clientMetaData: environment.clientMetaData)
                .map(IAPAction.verifiedPsiCashConsumable)
        ]
        
    case .verifiedPsiCashConsumable(let verifiedTx):
        guard case let .pendingVerificationResult(pendingTx) = state.iap.unverifiedPsiCashTx else {
            fatalErrorFeedbackLog("""
                found no unverified transaction equal to '\(verifiedTx)' \
                pending verification result
                """)
        }
        guard verifiedTx.value == pendingTx.value else {
            fatalErrorFeedbackLog("""
                transactions are not equal '\(verifiedTx)' != '\(pendingTx)'
                """)
        }
        state.iap.unverifiedPsiCashTx = .none
        return [
            environment.paymentQueue.finishTransaction(verifiedTx.value).mapNever(),
            environment.psiCashStore(.refreshPsiCashState).mapNever()
            ,
            .fireAndForget {
                PsiFeedbackLogger.info(withType: "IAP",
                                       json: ["event": "verified psicash consumable"])
            }
        ]
        
    case .transactionUpdate(let value):
        switch value {
        case .restoredCompletedTransactions:
            return [
                environment.appReceiptStore(._remoteReceiptRefreshResult(.success(()))).mapNever()
            ]
            
        case .updatedTransactions(let transactions):
            var effects = [Effect<IAPAction>]()
            
            for transaction in transactions {
                switch transaction.typedTransactionState {
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
                                fatalErrorFeedbackLog("unknown product \(String(describing: transaction))")
                                
                            case .psiCash:
                                switch state.iap.unverifiedPsiCashTx?.transaction
                                    .isEqualTransactionId(to: transaction) {
                                case .none:
                                    // There is no unverified psicash IAP transaction.
                                    
                                    // Updates balance state to reflect expected increase
                                    // in PsiCash balance.
                                    state.psiCashBalance.waitingForExpectedIncrease(
                                        withAddedReward: .zero,
                                        reason: .purchasedPsiCash,
                                        userConfigs: environment.userConfigs
                                    )
                                        
                                    finishTransaction = false
                                    state.iap.unverifiedPsiCashTx = .pendingVerification(
                                        UnverifiedPsiCashConsumableTransaction(value: transaction)
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
                                    let unverifiedTxId = state.iap.unverifiedPsiCashTx!
                                    .transaction.value.transactionIdentifier ?? "(none)"
                                    let newTxId = transaction.transactionIdentifier ?? "(none)"
                                    fatalErrorFeedbackLog("""
                                    cannot have two completed but unverified consumable purchases: \
                                        unverified transaction: '\(unverifiedTxId)', \
                                        new transaction: '\(newTxId)'
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
                    
                    if transactions.appReceiptUpdated {
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
        storeSend(.updatedTransactions(transactions))
    }
    
    @available(iOS 13.0, *)
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        // Do nothing.
    }
    
}
