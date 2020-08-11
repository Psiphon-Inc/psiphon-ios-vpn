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
import PsiApi
import Utilities

/// Typed wrapper for `SKPaymentTransaction.transactionIdentifier`.
///
/// This value has the same format as the transaction’s `transaction_id` in the receipt;
/// however, the values may not be the same.
/// Hence, these values are given a separate type to distinguish them from the
/// receipt `TransactionID` type.
///
/// - See Also: [Apple Documentation SKPaymentTransaction.transactionIdentifier]( https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411288-transactionidentifier)
public struct PaymentTransactionID: TypedIdentifier {
    public var rawValue: String { value }
    
    private let value: String
    
    public init?(rawValue: String) {
        self.value = rawValue
    }
}

/// Represents an in-app purchase transaction identifier present in the app receipt.
/// Apple Ref: https://developer.apple.com/documentation/appstorereceipts/transaction_id
public struct TransactionID: TypedIdentifier {
    public var rawValue: String { value }
    
    private let value: String
    
    public init?(rawValue: String) {
        self.value = rawValue
    }
}

/// Represents App Store in-app purchase original transaction identifier.
public struct OriginalTransactionID: TypedIdentifier {
    public var rawValue: String { value }
    
    private let value: String
    
    public init?(rawValue: String) {
        self.value = rawValue
    }
}

/// Represents App Store in-app purchase `web_order_line_item_id` that uniquely identifies
/// subscription purchases.
public struct WebOrderLineItemID: TypedIdentifier {
    public var rawValue: String { value }
    
    private let value: String
    
    public init?(rawValue: String) {
        self.value = rawValue
    }
}

/// Represents App Store in-app purchase product identifier.
public struct ProductID: TypedIdentifier {
    public var rawValue: String { value }
    
    private let value: String
    
    public init?(rawValue: String) {
        self.value = rawValue
    }
}

public struct ReceiptData: Hashable {
    /// Receipt file name.
    /// In debug build and Test Flight `filename` is expected to be "sandboxReceipt", however in production
    /// it is expected to be "receipt".
    public let filename: String
    /// Subscription in-app purchases within the receipt that have not expired at the time of `readDate`.
    public let subscriptionInAppPurchases: Set<SubscriptionIAPPurchase>
    /// Consumables in-app purchases within the receipt.
    public let consumableInAppPurchases: Set<ConsumableIAPPurchase>
    /// Receipt bytes.
    public let data: Data
    /// Date at which the receipt `data` was read.
    public let readDate: Date
    
    /// Whether the receipt file was created in the sandbox environment or not based on `filename`.
    /// Value is `nil` if `filename` is not one of the expected values.
    public var isReceiptSandbox: Bool? {
        switch filename {
        case "receipt":
            return false
        case "sandboxReceipt":
            return true
        default:
            return .none
        }
    }
    
    public init(
        filename: String,
        subscriptionInAppPurchases: Set<SubscriptionIAPPurchase>,
        consumableInAppPurchases: Set<ConsumableIAPPurchase>,
        data: Data,
        readDate: Date
    ) {
        self.filename = filename
        self.subscriptionInAppPurchases = subscriptionInAppPurchases
        self.consumableInAppPurchases = consumableInAppPurchases
        self.data = data
        self.readDate = readDate
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data == rhs.data
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(data)
    }
    
}

/// Represents an in-app purchase that is recorded in the receipt.
public protocol RecordedIAPPurchase: Hashable {
 
    /// Product ID string as create on Apple App Store.
    /// - ASN.1 Field Type: 1702
    /// - JSON Field Name: `product_id`
    var productID: ProductID { get }
    
    /// For a transaction that restores a previous transaction, this value is different from the
    /// transaction identifier of the original purchase transaction.
    /// In an auto-renewable subscription receipt, a new value for the transaction identifier is
    /// generated every time the subscription automatically renews or is restored.
    /// - ASN.1 Field Type: 1703
    /// - JSON Field Name: `transaction_id`
    var transactionID: TransactionID { get }
    
    /// In an auto-renewable subscription receipt, the purchase date is the
    /// date when the subscription was either purchased or renewed (with or without a lapse).
    /// For an automatic renewal that occurs on the expiration date of the current period,
    /// the purchase date is the start date of the next period, which is identical to the
    /// end date of the current period.
    /// - ASN.1 Field Type: 1704
    /// - JSON Field Name: `purchase_date`
    var purchaseDate: Date { get }
    
}

extension RecordedIAPPurchase {
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.transactionID == rhs.transactionID
    }
    
    public func hash(into hasher: inout Hasher) {
        // Transaction ID is unique.
        hasher.combine(self.transactionID)
    }
    
    /// Determines whether or not `paymentTransaction` matches this in-app purchase recorded
    /// in the App Store receipt.
    /// - Returns: `false` if `paymentTransaction` is not completed,
    /// otherwise matches transaction date and product ID.
    public func matches(paymentTransaction: PaymentTransaction) -> Bool {
        guard
            case .completed(.success(let completedTx)) = paymentTransaction.transactionState()
        else {
            return false
        }
        
        return (completedTx.transactionDate == self.purchaseDate &&
                    paymentTransaction.productID() == self.productID)
    }
    
}

/// Represents a consumable in-app purchase contained in the app receipt.
public struct ConsumableIAPPurchase: RecordedIAPPurchase {
    
    public let productID: ProductID
    public let transactionID: TransactionID
    public let purchaseDate: Date
    
    public init(productID: ProductID,
                transactionID: TransactionID,
                purchaseDate: Date) {
        self.productID = productID
        self.transactionID = transactionID
        self.purchaseDate = purchaseDate
    }
    
}

/// Represents a renewable-subscription in-app purchase contained in the app receipt.
/// - Note: `SubscriptionIAPPurchase` values are compared and hashed only by `transactionID`.
public struct SubscriptionIAPPurchase: RecordedIAPPurchase, Codable {
    
    /// Product ID string as create on Apple App Store.
    /// - ASN.1 Field Type: 1702
    /// - JSON Field Name: `product_id`
    public let productID: ProductID
    
    /// For a transaction that restores a previous transaction, this value is different from the
    /// transaction identifier of the original purchase transaction.
    /// In an auto-renewable subscription receipt, a new value for the transaction identifier is
    /// generated every time the subscription automatically renews or is restored.
    /// - ASN.1 Field Type: 1703
    /// - JSON Field Name: `transaction_id`
    public let transactionID: TransactionID
    
    /// The transaction identifier of the original purchase.
    /// - ASN.1 Field Type: 1705
    /// - JSON Field Name: `original_transaction_id`
    public let originalTransactionID: OriginalTransactionID
    
    /// The primary key for identifying subscription purchases.
    /// - Note: ASN.1 Field value is INTEGER, however it is parsed as a string.
    /// - ASN.1 Field Type: 1711
    /// - JSON Field Name: `web_order_line_item_id`
    public let webOrderLineItemID: WebOrderLineItemID
    
    /// In an auto-renewable subscription receipt, the purchase date is the
    /// date when the subscription was either purchased or renewed (with or without a lapse).
    /// For an automatic renewal that occurs on the expiration date of the current period,
    /// the purchase date is the start date of the next period, which is identical to the
    /// end date of the current period.
    /// - ASN.1 Field Type: 1704
    /// - JSON Field Name: `purchase_date`
    public let purchaseDate: Date
    
    /// Subscription's expiry date.
    /// - ASN.1 Field Type: 1708
    /// - JSON Field Name: `expires_date`
    public let expires: Date
    
    /// For an auto-renewable subscription, whether or not it is in the introductory price period.
    /// - ASN.1 Field Type: 1719
    /// - JSON Field Name: `is_in_intro_offer_period`
    public let isInIntroOfferPeriod: Bool
    
    /// Whether a pervious subscription in the receipt has the value true for `is_in_intro_offer_period`.
    /// This field is calculated from the receipt.
    public let hasBeenInIntroOfferPeriod: Bool
    
    public init(
        productID: ProductID,
        transactionID: TransactionID,
        originalTransactionID: OriginalTransactionID,
        webOrderLineItemID: WebOrderLineItemID,
        purchaseDate: Date,
        expires: Date,
        isInIntroOfferPeriod: Bool,
        hasBeenInIntroOfferPeriod: Bool
    ) {
        self.productID = productID
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.webOrderLineItemID = webOrderLineItemID
        self.purchaseDate = purchaseDate
        self.expires = expires
        self.isInIntroOfferPeriod = isInIntroOfferPeriod
        self.hasBeenInIntroOfferPeriod = hasBeenInIntroOfferPeriod
    }
    
    /// Returns true if given current time, the subscription is almost expired with a granularity of a minute.
    public func isApproximatelyExpired(
        getCurrentTime: () -> Date,
        compareDates: (Date, Date, Calendar.Component) -> ComparisonResult
    ) -> Bool {
        switch compareDates(getCurrentTime(), expires, .minute) {
        case .orderedAscending: return false
        case .orderedDescending: return true
        case .orderedSame: return true
        }
    }
    
}

extension Set where Element == SubscriptionIAPPurchase {
    
    public func sortedByExpiry() -> [Element] {
        self.sorted {
            $0.expires < $1.expires
        }
    }
    
}
