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
    case purchase(PurchasableProduct)
    case purchaseAdded(PurchaseAddedResult)
    case verifiedPsiCashConsumable(VerifiedPsiCashConsumableTransaction)
    case transactionUpdate(TransactionUpdate)
}

/// StoreKit transaction obersver
enum TransactionUpdate {
    case updatedTransactions([SKPaymentTransaction])
    case restoredCompletedTransactions(error: Error?)
}

struct IAPReducerState {
    var purchasing: PurchasingState
    var iap: IAPState
    let psiCashAuth: PsiCashAuthPackage
}

func iapReducer(state: inout IAPReducerState, action: IAPAction) -> [Effect<IAPAction>] {
    switch action {
    case .purchase(let product):
        guard case .none = state.purchasing else {
            return []
        }
        
        switch product {
        case .psiCash(product: _):
            guard state.psiCashAuth.hasSpenderToken else {
                state.purchasing = .iapError(ErrorEvent(
                    .failedToCreatePurchase(reason: "PsiCash data not present.")))
                return []
            }
            state.purchasing = .psiCash
            
        case .subscription(product: _):
            state.purchasing = .subscription
        }
        
        return [
            Current.paymentQueue.purchase(product)
                .map(IAPAction.purchaseAdded)
        ]
        
    case .purchaseAdded(let result):
        switch result {
        case .success(let addedPayment):
            state.purchasing = .none
            
            switch addedPayment.product {
            case .psiCash(product: _):
                state.iap.payments.insert(
                    PendingPayment(
                        payment: .psiCash(addedPayment.payment),
                        paidSuccessfully: .pending)
                )
            case .subscription(product: _, promise: let promise):
                state.iap.payments.insert(
                    PendingPayment(
                        payment: .subscription(addedPayment.payment, promise),
                        paidSuccessfully: .pending)
                )
            }
            
        case .failure(let errorEvent):
            if errorEvent.error.paymentCancelled {
                state.purchasing = .none
            } else {
                state.purchasing = .iapError(errorEvent
                    .map(PurchaseError.purchaseRequestError(error:)))
            }
        }
        return []
        
    case .verifiedPsiCashConsumable(let verifiedTransaction):
        state.iap.unverifiedPsiCashTransaction = .none
        return [
            Current.paymentQueue.finishTransaction(verifiedTransaction.value).mapNever(),
            .fireAndForget {
                Current.app.store.send(.psiCash(.refreshPsiCashState))
            },
            .fireAndForget {
                PsiFeedbackLogger.info(withType: "IAP",
                                       json: ["event": "verified psicash consumable"])
            }
        ]
        
    case .transactionUpdate(let value):
        switch value {
        case .restoredCompletedTransactions:
            return [
                .fireAndForget {
                    Current.app.store.send(.appReceipt(.receiptRefreshed(.success(()))))
                }
            ]
            
        case .updatedTransactions(let transactions):
            var effects = [Effect<IAPAction>]()
            
            for transaction in transactions {
                switch transaction.typedTransactionState {
                case .pending(_):
                    return []
                    
                case .completed(let completedState):
                    let finishTransaction: Bool
                    let newResult: Pending<Result<Unit, ErrorEvent<IAPError>>>
                    
                    switch completedState {
                    case let .failure(skError):
                        newResult = .completed(.failure(ErrorEvent(.storeKitError(skError))))
                        finishTransaction = true
                        
                    case let .success(success):
                        switch success {
                        case .purchased:
                            newResult = .completed(.success(.unit))
                            
                            switch try? AppStoreProductType.from(transaction: transaction) {
                            case .none:
                                fatalError("unknown product \(String(describing: transaction))")
                            case .psiCash:
                                let unverifiedTx =
                                    UnverifiedPsiCashConsumableTransaction(value: transaction)
                                state.iap.unverifiedPsiCashTransaction = unverifiedTx
                                finishTransaction = false
                                effects.append(
                                    verifyConsumable(unverifiedTx)
                                        .map(IAPAction.verifiedPsiCashConsumable)
                                )
                                
                            case .subscription:
                                finishTransaction = true
                            }
                            
                        case .restored :
                            newResult = .completed(.success(.unit))
                            finishTransaction = true
                        }
                    }
                    
                    // Updates PendingPayment result value.
                    state.iap.payments = state.iap.payments.mutateResult(
                        transaction: transaction,
                        to: newResult
                    )
                    
                    if finishTransaction {
                        effects.append(
                            Current.paymentQueue.finishTransaction(transaction).mapNever()
                        )
                    }
                    
                    if transactions.appReceiptUpdated {
                        effects.append(
                            .fireAndForget {
                                Current.app.store.send(.appReceipt(.receiptRefreshed(.success(()))))
                            }
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
class PaymentTransactionDelegate: StoreDelegate<TransactionUpdate>,
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
        sendOnMain(.restoredCompletedTransactions(error: error))
    }
    
    // Sent when all transactions from the user's purchase history have
    // successfully been added back to the queue.
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        sendOnMain(.restoredCompletedTransactions(error: .none))
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
        sendOnMain(.updatedTransactions(transactions))
    }
    
    @available(iOS 13.0, *)
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        // Do nothing.
    }
    
}

extension Set where Element == PendingPayment {
    
    // TODO! write a more proper function
    func mutateResult(
        transaction: SKPaymentTransaction, to newValue: Pending<Result<Unit, ErrorEvent<IAPError>>>
    ) -> Set<PendingPayment> {
        Set(self.map { (pendingPayment: PendingPayment) -> PendingPayment in
            guard transaction.payment.isEqual(pendingPayment.payment.paymentObject) else {
                return pendingPayment
            }
            return PendingPayment(payment: pendingPayment.payment,
                                  paidSuccessfully: newValue)
        })
    }
    
}

