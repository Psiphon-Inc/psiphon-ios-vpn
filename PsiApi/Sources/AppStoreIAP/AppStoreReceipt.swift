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

/// Represents App Store in-app purchase product identifier.
public struct ProductID: TypedIdentifier {
    public var rawValue: String { value }
    
    private let value: String
    
    public init?(rawValue: String) {
        self.value = rawValue
    }
}

public struct ReceiptData: Equatable {
    /// Subscription in-app purchases within the receipt that have not expired at the time of `readDate`.
    public let subscriptionInAppPurchases: Set<SubscriptionIAPPurchase>
    /// Consumables in-app purchases within the receipt.
    public let consumableInAppPurchases: Set<ConsumableIAPPurchase>
    /// Receipt bytes.
    public let data: Data
    /// Date at which the receipt `data` was read.
    public let readDate: Date
    
    public init(
        subscriptionInAppPurchases: Set<SubscriptionIAPPurchase>,
        consumableInAppPurchases: Set<ConsumableIAPPurchase>,
        data: Data,
        readDate: Date
    ) {
        self.subscriptionInAppPurchases = subscriptionInAppPurchases
        self.consumableInAppPurchases = consumableInAppPurchases
        self.data = data
        self.readDate = readDate
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data == rhs.data
    }
    
}

/// Represents a consumable in-app purchase contained in the app receipt.
public struct ConsumableIAPPurchase: Hashable {
    public let productID: ProductID
    public let transactionID: TransactionID
    
    public init(productID: ProductID, transactionID: TransactionID) {
        self.productID = productID
        self.transactionID = transactionID
    }
    
}

/// Represents a renewable-subscription in-app purchase contained in the app receipt.
/// - Note: `SubscriptionIAPPurchase` values are compared and hashed only by `transactionID`.
public struct SubscriptionIAPPurchase: Hashable, Codable {
    
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
        purchaseDate: Date,
        expires: Date,
        isInIntroOfferPeriod: Bool,
        hasBeenInIntroOfferPeriod: Bool
    ) {
        self.productID = productID
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
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
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.transactionID == rhs.transactionID
    }
    
    public func hash(into hasher: inout Hasher) {
        // Transaction ID is unique.
        hasher.combine(self.transactionID)
    }
}

extension Set where Element == SubscriptionIAPPurchase {
    
    public func sortedByExpiry() -> [Element] {
        self.sorted {
            $0.expires < $1.expires
        }
    }
    
}
