/*
 * Copyright (c) 2019, Psiphon Inc.
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
import StoreKit
import Promises
import ReactiveSwift

enum LocalizedPrice: Equatable {
    case free
    case localizedPrice(price: Double, priceLocale: Locale)
}

extension LocalizedPrice {
    
    static func makeLocalizedPrice(skProduct: SKProduct) -> Self {
        guard skProduct.price.doubleValue > 0.0 else {
            fatalErrorFeedbackLog("SKProduct cannot have value 0")
        }
        return .localizedPrice(price: skProduct.price.doubleValue,
                               priceLocale: skProduct.priceLocale)
    }
    
}

enum ProductIdError: Error {
    case invalidString(String)
}

struct AppStoreProduct: Hashable {
    let type: AppStoreProductType
    let skProduct: SKProduct

    init(_ skProduct: SKProduct) throws {
        let type = try AppStoreProductType.from(skProduct: skProduct)
        self.type = type
        self.skProduct = skProduct
    }
}

enum AppStoreProductType: String {
    case subscription = "subscriptionProductIds"
    case psiCash = "psiCashProductIds"

    private static func from(productIdentifier: String) throws -> AppStoreProductType {
        if productIdentifier.hasPrefix("ca.psiphon.Psiphon.Consumable.PsiCash.") {
            return .psiCash
        }

        if productIdentifier.hasPrefix("ca.psiphon.Psiphon.") {
            return .subscription
        }

        throw ProductIdError.invalidString(productIdentifier)
    }

    static func from(transaction: PaymentTransaction) throws -> AppStoreProductType {
        return try .from(productIdentifier: transaction.productID())
    }
    
    static func from(transaction: SKPaymentTransaction) throws -> AppStoreProductType {
        return try from(productIdentifier: transaction.payment.productIdentifier)
    }

    static func from(skProduct: SKProduct) throws -> AppStoreProductType {
        return try from(productIdentifier: skProduct.productIdentifier)
    }
}

/// Represents product identifiers in-app purchase products that are supported.
struct SupportedAppStoreProductIDs: Equatable {
    let values: Set<ProductID>

    private init(for type: AppStoreProductType, validator: (Set<String>) -> Bool) {
        values = try! plistReader(key: type.rawValue, toType: Set<String>.self)
    }

    static func subscription() -> Self {
        return .init(for: .subscription) { ids -> Bool in
            // TODO: do some validation here.
            return true
        }
    }

    static func psiCash() -> Self {
        return .init(for: .psiCash) { ids -> Bool in
            // TODO: do some validation here.
            return true
        }
    }
}

struct PaymentTransaction: Equatable {
    
    /// Refines `SKPaymentTransaction` state.
    enum TransactionState: Equatable {
        
        enum PendingTransactionState: Equatable {
            case purchasing
            case deferred
        }
        
        enum CompletedTransactionState: Equatable {
            case purchased
            case restored
        }
        
        case pending(PendingTransactionState)
        case completed(Result<CompletedTransactionState, Either<SKError, SystemError>>)
    }
    
    let transactionID: () -> TransactionID
    let transactionDate: () -> Date
    let productID: () -> String
    let transactionState: () -> TransactionState
    private let isEqual: (PaymentTransaction) -> Bool
    
    let skPaymentTransaction: () -> SKPaymentTransaction?
    
    func isEqualTransactionID(to other: PaymentTransaction) -> Bool {
        self.transactionID() == other.transactionID()
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.skPaymentTransaction(), rhs.skPaymentTransaction()) {
        case (nil, nil):
            return lhs.transactionID() == rhs.transactionID()
        case let (.some(lobj), .some(robj)):
            return lobj.isEqual(robj)
        default:
            fatalErrorFeedbackLog("""
                expected lhs and rhs to have same underlying type: \
                lhs: '\(String(describing: lhs))' \
                rhs: '\(String(describing: rhs))'
                """)
        }
    }
}

extension PaymentTransaction.TransactionState {
    
    /// Indicates whether the app receipt has been updated.
    var appReceiptUpdated: Bool {
        // Each case is explicitly typed as returning true or false
        // to ensure function correctness in future updates.
        switch self {
        case let .completed(completed):
            switch completed {
            case .success(.purchased): return true
            case .success(.restored): return true
            case .failure(_): return false
            }
        case let .pending(pending):
            switch pending {
            case .deferred: return false
            case .purchasing: return false
            }
        }
    }
    
}

extension PaymentTransaction {
    
    /// Created PaymentTransaction holds a strong reference to the `skPaymentTransaction` object.
    static func make(from skPaymentTransaction: SKPaymentTransaction) -> Self {
        PaymentTransaction(
            transactionID: { () -> TransactionID in
                TransactionID(stringLiteral: skPaymentTransaction.transactionIdentifier!)
            },
            transactionDate: { () -> Date in
                skPaymentTransaction.transactionDate!
            },
            productID: { () -> String in
                skPaymentTransaction.payment.productIdentifier
            },
            transactionState: { () -> TransactionState in
                switch skPaymentTransaction.transactionState {
                case .purchasing:
                    return .pending(.purchasing)
                case .deferred:
                    return .pending(.deferred)
                case .purchased:
                    return .completed(.success(.purchased))
                case .restored:
                    return .completed(.success(.restored))
                case .failed:
                    // Error is non-null when state is failed.
                    let someError = skPaymentTransaction.error!
                    if let skError = someError as? SKError {
                        return .completed(.failure(.left(skError)))
                    } else {
                        return .completed(.failure(.right(someError as SystemError)))
                    }
                @unknown default:
                    fatalErrorFeedbackLog("""
                        unknown transaction state \(skPaymentTransaction.transactionState)
                        """)
                }
            },
            isEqual: { other -> Bool in
                skPaymentTransaction.isEqual(other)
            },
            skPaymentTransaction: { () -> SKPaymentTransaction? in
                skPaymentTransaction
            }
        )
    }
    
}
