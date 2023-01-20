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
import Utilities
import PsiApi

// Supported App Store products
public enum AppStoreProductType: String, CaseIterable {
    case subscription
    case psiCash
    
    /// Returns true if self is a consumable App Store product type.
    public var isConsumable: Bool {
        switch self {
        case .subscription: return false
        case .psiCash: return true
        }
    }
    
    public var prefix: AppStoreProductIdPrefixes {
        switch self {
        case .subscription: return .subscription
        case .psiCash: return .psiCash
        }
    }
}

public enum LocalizedPrice: Hashable {
    case free
    case localizedPrice(price: Double, priceLocale: PriceLocale)
}

extension LocalizedPrice {
    
    public static func makeLocalizedPrice(skProduct: SKProduct) -> Self {
        guard skProduct.price.doubleValue > 0.0 else {
            fatalError("SKProduct cannot have value 0")
        }
        return .localizedPrice(price: skProduct.price.doubleValue,
                               priceLocale: PriceLocale(skProduct.priceLocale))
    }
    
}

public enum ProductIdError: Error {
    case invalidString(String)
}

/// Wraps `SKPayment` object.
public struct Payment: Hashable {

    public let productID: ProductID
    public let quantity: Int
    public let skPaymentObj: SKPayment?
    public let skPaymentHash: Int

    init(productID: ProductID, quantity: Int = 1) {
        self.productID = productID
        self.quantity = quantity
        self.skPaymentObj = nil
        self.skPaymentHash = productID.hashValue
    }
    
    public init(
        productID: ProductID,
        quantity: Int,
        skPaymentObj: SKPayment?,
        skPaymentHash: Int
    ) {
        self.productID = productID
        self.quantity = quantity
        self.skPaymentObj = skPaymentObj
        self.skPaymentHash = skPaymentHash
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.skPaymentHash)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.skPaymentHash == rhs.skPaymentHash
    }
    
}

/// Wraps SKProduct.
public struct AppStoreProduct: Hashable, CustomStringFeedbackDescription {
    
    public let type: AppStoreProductType
    public let productID: ProductID
    public let localizedDescription: String
    public let price: LocalizedPrice
    
    // Underlying SKProduct object
    public let skProductRef: SKProduct?

    public var description: String {
        // Excludes NSObject `skProductRef`.
        """
        AppStoreProduct(type: \(type), \
        productID: \(productID), \
        localizedDescription: \"\(localizedDescription)\", \
        price: \(price))
        """
    }
    
    public init(
        type: AppStoreProductType,
        productID: ProductID,
        localizedDescription: String,
        price: LocalizedPrice,
        skProductRef: SKProduct?
    ) {
        self.type = type
        self.productID = productID
        self.localizedDescription = localizedDescription
        self.price = price
        self.skProductRef = skProductRef
    }
}


public enum AppStoreProductIdPrefixes: String, CaseIterable {
    case subscription = "ca.psiphon.Psiphon"
    case psiCash = "ca.psiphon.Psiphon.Consumable.PsiCash"
    
    static func estimateProductTypeFromPrefix(_ productID: ProductID) -> AppStoreProductType? {
        if productID.rawValue.contains(AppStoreProductIdPrefixes.psiCash.rawValue) {
            return .psiCash
        } else if productID.rawValue.contains(AppStoreProductIdPrefixes.subscription.rawValue) {
            return .subscription
        } else {
            return nil
        }
    }
}

/// Represents product identifiers in-app purchase products that are supported.
public struct SupportedAppStoreProducts: Equatable {
    
    public let supported: [AppStoreProductType: Set<ProductID>]
    private let reversed: [ProductID: AppStoreProductType]
    
    public init(_ supportedSeq: [(AppStoreProductType, Set<ProductID>)]) {
        
        self.supported = Dictionary(uniqueKeysWithValues: supportedSeq)
        
        self.reversed = Dictionary(uniqueKeysWithValues:
            supportedSeq.flatMap { pair -> [(ProductID, AppStoreProductType)] in
                return pair.1.map { ($0, pair.0) }
            }
        )
    }
    
    public init(_ supportedSeq: [(AppStoreProductType, ProductID)]) {
    
        let supportedKeyWithValues = AppStoreProductType.allCases
            .map { possibleType -> (AppStoreProductType, Set<ProductID>) in
                
                let sameTypeProductIDs: [ProductID] = supportedSeq
                    .filter { productTypeProductIdPair -> Bool in
                        productTypeProductIdPair.0 == possibleType
                    }
                    .map { $0.1 }
                
                return (possibleType, Set(sameTypeProductIDs))
        }
        
        self.supported = Dictionary(uniqueKeysWithValues: supportedKeyWithValues)
        
        self.reversed = Dictionary(uniqueKeysWithValues:supportedSeq.map { ($0.1, $0.0) })
    }

    public func isSupportedProduct(_ productID: ProductID) -> AppStoreProductType? {
        return reversed[productID]
    }
}

/// Wraps a `SKPaymentTransaction` object and provides better typing of it's state.
/// A payment transaction represents an object in the StoreKit payment queue.
public final class AppStorePaymentTransaction: Equatable {

    /// Refines `SKPaymentTransaction` state.
    /// - Note: `SKPaymentTransaction.transactionDate` is only valid if state is
    /// `SKPaymentTransactionStatePurchased` or `SKPaymentTransactionStateRestored`.
    public enum TransactionState: Equatable {
        
        /// Represents pending state of `SKPaymentTransactionState`.
        /// https://developer.apple.com/documentation/storekit/skpaymenttransactionstate
        public enum PendingTransactionState: Equatable {
            /// A transaction that is being processed by the App Store.
            case purchasing
            /// A transaction that is in the queue, but its final status is pending external action such as Ask to Buy.
            case deferred
        }
        
        public enum TransactionErrorState: HashableError {
            /// A `SKPaymentTransaction` is invalid if its state does not match Apple's documentation.
            /// This might indicate that the device is jailbroken.
            case invalidTransaction
            /// Represents an error emitted by `StoreKit` processing an in-app purchase.
            case error(Either<SystemError<Int>, SystemError<SKError.Code>>)
        }
        
        case pending(PendingTransactionState)

        case completed(Result<CompletedTransaction, TransactionErrorState>)
    }
    
    /// Represents a `SKPaymentTransaction` with state `.purchased` or `.restored`.
    /// Two `CompletedTransaction` objects are equal if their payment transdaction identifier is equal.
    /// Ref: https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411288-transactionidentifier
    public struct CompletedTransaction: Equatable {
        
        /// Whether or not this completed transaction was restored or not.
        public let isRestored: Bool
        
        /// Unique identifier of a successful payment transaction.
        public let paymentTransactionID: PaymentTransactionID
        
        public let transactionDate: Date
        
        public init(
            isRestored: Bool,
            paymentTransactionID: PaymentTransactionID,
            transactionDate: Date
        ) {
            self.isRestored = isRestored
            self.paymentTransactionID = paymentTransactionID
            self.transactionDate = transactionDate
        }
        
        public static func == (lhs: CompletedTransaction, rhs: CompletedTransaction) -> Bool {
            return lhs.paymentTransactionID == rhs.paymentTransactionID
        }
        
    }
    
    public let productID: () -> ProductID
    public let transactionState: () -> TransactionState
    public let payment: () -> Payment
    public let isEqual: (AppStorePaymentTransaction) -> Bool
    
    public let skPaymentTransaction: () -> SKPaymentTransaction?
    
    public init(
        productID: @escaping () -> ProductID,
        transactionState: @escaping () -> AppStorePaymentTransaction.TransactionState,
        payment: @escaping () -> Payment,
        isEqual: @escaping (AppStorePaymentTransaction) -> Bool,
        skPaymentTransaction: @escaping () -> SKPaymentTransaction?
    ) {
        self.productID = productID
        self.transactionState = transactionState
        self.payment = payment
        self.isEqual = isEqual
        self.skPaymentTransaction = skPaymentTransaction
    }
    
    public static func == (lhs: AppStorePaymentTransaction, rhs: AppStorePaymentTransaction) -> Bool {
        lhs.isEqual(rhs)
    }
}

extension AppStorePaymentTransaction {
    
    /// Returns `CompletedTransaction` if this transaction is completed, otherwise returns `nil`.
    var completedTransaction: CompletedTransaction? {
        guard case .completed(.success(let completedTx)) =  self.transactionState() else {
            return nil
        }
        return completedTx
    }
    
}

extension AppStorePaymentTransaction.TransactionState {
    
    /// Whether or not the App Store purchase is pending completed or is completed/failed.
    var pending: Bool {
        switch self {
        case .pending(_): return true
        case .completed(_): return false
        }
    }
    
    /// App Store app receipt is expected to be updated for a completed IAP transaction.
    var isReceiptUpdated: Bool {
        // Each case is explicitly typed as returning true or false
        // to ensure function correctness in future updates.
        switch self {
        case let .completed(completed):
            switch completed {
            case .success(_): return true
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

extension AppStorePaymentTransaction.TransactionState: FeedbackDescription {}

extension AppStorePaymentTransaction: CustomFieldFeedbackDescription {
    
    public var feedbackFields: [String: CustomStringConvertible] {
        ["productID": self.productID(),
         "transactionState": makeFeedbackEntry(self.transactionState())]
    }
    
}
