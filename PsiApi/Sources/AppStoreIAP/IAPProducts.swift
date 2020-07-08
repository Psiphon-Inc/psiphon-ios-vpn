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
    case localizedPrice(price: Double, priceLocale: Locale)
}

extension LocalizedPrice {
    
    public static func makeLocalizedPrice(skProduct: SKProduct) -> Self {
        guard skProduct.price.doubleValue > 0.0 else {
            fatalError("SKProduct cannot have value 0")
        }
        return .localizedPrice(price: skProduct.price.doubleValue,
                               priceLocale: skProduct.priceLocale)
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
public struct AppStoreProduct: Hashable {
    
    public let type: AppStoreProductType
    public let productID: ProductID
    public let localizedDescription: String
    public let price: LocalizedPrice
    
    // Underlying SKProduct object
    public let skProductRef: SKProduct?
    
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

public struct PaymentTransaction: Equatable {

    /// Refines `SKPaymentTransaction` state.
    /// - Note: `SKPaymentTransaction.transactionDate` is only valid if state is
    /// `SKPaymentTransactionStatePurchased` or `SKPaymentTransactionStateRestored`.
    public enum TransactionState: Equatable {
        
        public enum PendingTransactionState: Equatable {
            case purchasing
            case deferred
        }
        
        public enum TransactionErrorState: HashableError {
            /// A `SKPaymentTransaction` is invalid if its state does not match Apple's documentation.
            /// This might indicate that the device is jailbroken.
            case invalidTransaction
            /// Represents an error emitted by `StoreKit` processing an in-app purchase.
            case error(Either<SystemError, SKError>)
        }
        
        case pending(PendingTransactionState)

        case completed(Result<CompletedTransaction, TransactionErrorState>)
    }
    
    /// Represents a `SKPaymentTransaction` with state `.purchased` or `.completed`.
    public struct CompletedTransaction: Equatable {
        
        public enum State: Equatable {
            case purchased
            case restored
        }
        
        public let completedState: State
        public let paymentTransactionID: PaymentTransactionID
        public let transactionDate: Date
        
        public init(completedState: PaymentTransaction.CompletedTransaction.State,
                    paymentTransactionID: PaymentTransactionID,
                    transactionDate: Date) {
            self.completedState = completedState
            self.paymentTransactionID = paymentTransactionID
            self.transactionDate = transactionDate
        }
        
    }
    
    public let productID: () -> ProductID
    public let transactionState: () -> TransactionState
    public let payment: () -> Payment
    public let isEqual: (PaymentTransaction) -> Bool
    
    public let skPaymentTransaction: () -> SKPaymentTransaction?
    
    public init(productID: @escaping () -> ProductID,
                transactionState: @escaping () -> PaymentTransaction.TransactionState,
                payment: @escaping () -> Payment,
                isEqual: @escaping (PaymentTransaction) -> Bool,
                skPaymentTransaction: @escaping () -> SKPaymentTransaction?) {
        self.productID = productID
        self.transactionState = transactionState
        self.payment = payment
        self.isEqual = isEqual
        self.skPaymentTransaction = skPaymentTransaction
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isEqual(rhs)
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
    
    /// Represents whether for a given App Store transaction, `finishTransaction(_:)`
    /// should be called on the transaction.
    public enum FinishAppStoreTransaction: Equatable {
        /// It's an error to call `finishTransaction(_:)` on the transaction given it's current state.
        case nop
        /// `finishTransaction(_:)` should be called immediately.
        case immediately
        /// `finishTransaction(_:)` should be called after all the deliverables are delivered.
        case afterDeliverablesDelivered
    }
    
    /// `shouldFinishTransactionImmediately` determines whether or not to
    /// call `finishTransaction(_:)` on an App Store IAP before any deliverables are delivered
    /// based on current transaction state and the provided `productType`.
    public func shouldFinishTransactionImmediately(
        productType: AppStoreProductType
    ) -> FinishAppStoreTransaction {
        switch self {
        case .pending(_):
            return .nop
            
        case .completed(.failure(_)):
            return .immediately
            
        case .completed(.success(_)):
            switch productType {
            case .psiCash:
                // PsiCash purchases are consumables. The receipt may
                // no longer contain the transaction after it is finished.
                return .afterDeliverablesDelivered
            case .subscription:
                // Subscription purchases are auto-renewable subscriptions.
                // The transaction can be finished either right after it has
                // completed, or like the case of `PsiCash` consumable purchase
                // can be finished after all the deliverables have been delivered.
                return .immediately
            }
        }
    }
    
}

extension PaymentTransaction.TransactionState: FeedbackDescription {}

extension PaymentTransaction: CustomFieldFeedbackDescription {
    
    public var feedbackFields: [String: CustomStringConvertible] {
        ["productID": self.productID(),
         "transactionState": makeFeedbackEntry(self.transactionState())]
    }
    
}
