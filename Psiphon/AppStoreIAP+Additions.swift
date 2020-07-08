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
import Utilities
import AppStoreIAP
import PsiApi


extension SupportedAppStoreProducts {
    static func fromPlists(types: [AppStoreProductType]) -> SupportedAppStoreProducts {
        SupportedAppStoreProducts(
            types.map { type -> (AppStoreProductType, Set<ProductID>) in
                let rawValues = try! plistReader(key: type.plistFile, toType: [String].self)
                let productIDs = Set(rawValues.compactMap { ProductID(rawValue: $0) })
                return (type, productIDs)
            }
        )
    }
}

extension PaymentQueue {
    
    static let `default` = PaymentQueue(
        transactions: {
            Effect {
                SKPaymentQueue.default().transactions.map(PaymentTransaction.make(from:))
            }
        },
        addPayment: { product in
            .fireAndForget {
                let skPayment = SKPayment(product: product.skProductRef!)
                SKPaymentQueue.default().add(skPayment)
            }
        },
        addObserver: { observer in
            .fireAndForget {
                SKPaymentQueue.default().add(observer)
            }
        },
        removeObserver: { observer in
            .fireAndForget {
                SKPaymentQueue.default().remove(observer)
            }
        },
        finishTransaction: { transaction in
            .fireAndForget {
                guard let skPaymentTransaction = transaction.skPaymentTransaction() else {
                    return
                }
                SKPaymentQueue.default().finishTransaction(skPaymentTransaction)
            }
        })
    
}

extension ReceiptData: FeedbackDescription {}

extension SKProduct {
    var typedProductID: ProductID? {
        ProductID(rawValue: self.productIdentifier)
    }
}

extension SKPayment {
    var typedProductID: ProductID? {
        ProductID(rawValue: self.productIdentifier)
    }
}

extension Payment {
    
    static func from(skPayment: SKPayment) -> Payment {
        Payment(
            productID: skPayment.typedProductID!,
            quantity: skPayment.quantity,
            skPaymentObj: skPayment,
            skPaymentHash: skPayment.hash
        )
    }
    
}
    
extension AppStoreProductType {
    
    var plistFile: String {
        switch self {
        case .subscription:
            return "subscriptionProductIds"
        case .psiCash:
            return "psiCashProductIds"
        }
    }
    
}

extension AppStoreProduct {
    
    public static func from(
        skProduct: SKProduct,
        isSupportedProduct: (ProductID) -> AppStoreProductType?
    ) throws -> AppStoreProduct {
        
        guard let type = isSupportedProduct(skProduct.typedProductID!) else {
            throw ErrorRepr(repr: "Product ID '\(skProduct.productIdentifier)' not supported")
        }
        
        return AppStoreProduct(
            type: type,
            productID: ProductID(rawValue: skProduct.productIdentifier)!,
            localizedDescription: skProduct.localizedDescription,
            price: .makeLocalizedPrice(skProduct: skProduct),
            skProductRef: skProduct
        )
    }
    
}

extension PaymentTransaction {
        
    /// Created PaymentTransaction holds a strong reference to the `skPaymentTransaction` object.
    static func make(from skPaymentTransaction: SKPaymentTransaction) -> Self {
        PaymentTransaction(
            productID: { () -> ProductID in
                ProductID(rawValue: skPaymentTransaction.payment.productIdentifier)!
            },
            transactionState: { () -> TransactionState in
                switch skPaymentTransaction.transactionState {
                case .purchasing:
                    return .pending(.purchasing)
                    
                case .deferred:
                    return .pending(.deferred)
                    
                case .purchased:
                    
                    // https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411288-transactionidentifier
                    // The contents of `transactionIdentifier` and `transactionDate` properties are
                    // undefined except when transactionState is set to `.purchased` or `.restored`.
                    
                    guard let paymentTxID = skPaymentTransaction.transactionIdentifier else {
                        // The transaction is invalid probably due to a jailbroken device.
                        return .completed(.failure(.invalidTransaction))
                    }
                    
                    guard let transactionDate = skPaymentTransaction.transactionDate else {
                        // The transaction is invalid probably due to a jailbroken device.
                        return .completed(.failure(.invalidTransaction))
                    }
                    
                    return .completed(.success(
                        PaymentTransaction.CompletedTransaction(
                            completedState: .purchased,
                            paymentTransactionID: PaymentTransactionID(rawValue: paymentTxID)!,
                            transactionDate: transactionDate)))
                    
                case .restored:
                    
                    // https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411288-transactionidentifier
                    // The contents of `transactionIdentifier` and `transactionDate` properties are
                    // undefined except when transactionState is set to `.purchased` or `.restored`.
                    
                    
                    guard let paymentTxID = skPaymentTransaction.transactionIdentifier else {
                        // The transaction is invalid probably due to a jailbroken device.
                        return .completed(.failure(.invalidTransaction))
                    }
                    
                    guard let transactionDate = skPaymentTransaction.transactionDate else {
                        // The transaction is invalid probably due to a jailbroken device.
                        return .completed(.failure(.invalidTransaction))
                    }
                    
                    return .completed(.success(
                        PaymentTransaction.CompletedTransaction(
                            completedState: .restored,
                            paymentTransactionID: PaymentTransactionID(rawValue: paymentTxID)!,
                            transactionDate: transactionDate)))
                    
                case .failed:
                    // Error is non-null when state is failed.
                    let someError = skPaymentTransaction.error!
                    if let skError = someError as? SKError {
                        return .completed(.failure(.error(.right(skError))))
                    } else {
                        return .completed(.failure(.error(.left(SystemError(someError)))))
                    }
                    
                @unknown default:
                    fatalError("""
                        unknown transaction state \(skPaymentTransaction.transactionState)
                        """)
                }
            },
            payment: { () -> Payment in
                Payment.from(skPayment: skPaymentTransaction.payment)
            },
            isEqual: { other -> Bool in
                skPaymentTransaction.isEqual(other.skPaymentTransaction())
            },
            skPaymentTransaction: { () -> SKPaymentTransaction? in
                skPaymentTransaction
            }
        )
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
        storeSend(.restoredCompletedTransactions(error: SystemError(error)))
    }
    
    // Sent when all transactions from the user's purchase history have
    // successfully been added back to the queue.
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        storeSend(.restoredCompletedTransactions(error: .none))
    }
    
    // Sent when the transaction array has changed (additions or state changes).
    // Client should check state of transactions and finish as appropriate.
    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        storeSend(
            .updatedTransactions(transactions.map(PaymentTransaction.make(from:)))
        )
    }
    
}


