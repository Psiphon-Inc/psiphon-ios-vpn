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

/// Represents an in-app purchase transaction identifier present in the app receipt.
/// Apple Ref: https://developer.apple.com/documentation/appstorereceipts/transaction_id
struct TransactionID: ExpressibleByStringLiteral, Hashable, Codable, CustomStringConvertible {
    typealias StringLiteralType = String
    
    private let value: String
    
    init(stringLiteral value: String) {
        self.value = value
    }
    
    var description: String {
        self.value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(stringLiteral: try container.decode(String.self))
    }
    
}

struct OriginalTransactionID: ExpressibleByStringLiteral, Hashable, Codable,
CustomStringConvertible
{
    typealias StringLiteralType = String
    
    private let value: String
    
    init(stringLiteral value: String) {
        self.value = value
    }
    
    var description: String {
        self.value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(stringLiteral: try container.decode(String.self))
    }
    
}

/// Represents in-app purchase product identifier
typealias ProductID = String

struct ReceiptData: Equatable {
    /// Subscription in-app purchases within the receipt that have not expired at the time of `readDate`.
    let subscriptionInAppPurchases: Set<SubscriptionIAPPurchase>
    /// Consumables in-app purchases within the receipt.
    let consumableInAppPurchases: Set<ConsumableIAPPurchase>
    /// Receipt bytes.
    let data: Data
    /// Date at which the receipt `data` was read.
    let readDate: Date
    
    /// Parses local app receipt and returns a `ReceiptData` object.
    /// If no receipt file is found at path pointed to by the `Bundle` `.none` is returned.
    /// - Note: It is expected for the `Bundle` object to have a valid
    static func parseLocalReceipt(
        appBundle: PsiphonBundle,
        consumableProductIDs: Set<ProductID>,
        subscriptionProductIDs: Set<ProductID>,
        getCurrentTime: () -> Date,
        compareDates: (Date, Date, Calendar.Component) -> ComparisonResult,
        feedbackLogger: FeedbackLogger
    ) -> ReceiptData? {
        // TODO: This function should return a result type and not log errors directly here.
        let receiptURL = appBundle.appStoreReceiptURL
        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            return .none
        }
        
        let data: Data
        do {
            try data = Data(contentsOf: receiptURL)
        } catch {
            feedbackLogger.immediate(
                .error, "failed to read app receipt: '\(String(describing: error))'")
            return .none
        }
        
        let readDate = getCurrentTime()
        
        guard let parsedData = AppStoreParsedReceiptData.parseReceiptData(data) else {
            feedbackLogger.immediate(.error, "failed to parse app receipt")
            return .none
        }
        
        // Validate bundle identifier.
        guard parsedData.bundleIdentifier == appBundle.bundleIdentifier else {
            fatalError("""
                Receipt bundle identifier '\(String(describing: parsedData.bundleIdentifier))'
                does not match app bundle identifier '\(appBundle.bundleIdentifier)'
                """)
        }
        
        // Computes whether any of subscription purchases in the receipt
        // have the "is_in_intro_offer_period" set to true.
        let hasSubscriptionBeenInIntroOfferPeriod = parsedData.inAppPurchases.filter {
            subscriptionProductIDs.contains($0.productIdentifier)
        }.map {
            $0.isInIntroPeriod
        }.contains(true)

        // Filters out subscription purchases that have already expired at by `readDate`.
        let subscriptionPurchases = Set(parsedData.inAppPurchases
            .compactMap { parsedIAP -> SubscriptionIAPPurchase? in
                guard subscriptionProductIDs.contains(parsedIAP.productIdentifier) else {
                    return nil
                }
                let purchase = SubscriptionIAPPurchase(
                    productID: parsedIAP.productIdentifier,
                    transactionID: TransactionID(stringLiteral: parsedIAP.transactionID),
                    originalTransactionID: OriginalTransactionID(stringLiteral:
                        parsedIAP.originalTransactionID),
                    purchaseDate: parsedIAP.purchaseDate,
                    expires: parsedIAP.expiresDate!,
                    isInIntroOfferPeriod: parsedIAP.isInIntroPeriod,
                    hasBeenInIntroOfferPeriod: hasSubscriptionBeenInIntroOfferPeriod
                )
                
                let approxExpired = purchase.isApproximatelyExpired(getCurrentTime: { readDate },
                                                                    compareDates: compareDates)
                guard !approxExpired else {
                    return nil
                }
                return purchase
        })
        
        let consumablePurchases = Set(parsedData.inAppPurchases
            .compactMap { parsedIAP -> ConsumableIAPPurchase? in
                guard consumableProductIDs.contains(parsedIAP.productIdentifier) else {
                    return nil
                }
                return ConsumableIAPPurchase(
                    productID: parsedIAP.productIdentifier,
                    transactionID: TransactionID(stringLiteral: parsedIAP.transactionID)
                )
        })
        
        return ReceiptData(subscriptionInAppPurchases: subscriptionPurchases,
                           consumableInAppPurchases: consumablePurchases,
                           data: data, readDate: readDate)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data == rhs.data
    }
    
}

/// Represents a consumable in-app purchase contained in the app receipt.
struct ConsumableIAPPurchase: Hashable {
    let productID: ProductID
    let transactionID: TransactionID
}

/// Represents a renewable-subscription in-app purchase contained in the app receipt.
/// - Note: `SubscriptionIAPPurchase` values are compared and hashed only by `transactionID`.
struct SubscriptionIAPPurchase: Hashable, Codable {
    
    /// Product ID string as create on Apple App Store.
    /// - ASN.1 Field Type: 1702
    /// - JSON Field Name: `product_id`
    let productID: ProductID
    
    /// For a transaction that restores a previous transaction, this value is different from the
    /// transaction identifier of the original purchase transaction.
    /// In an auto-renewable subscription receipt, a new value for the transaction identifier is
    /// generated every time the subscription automatically renews or is restored.
    /// - ASN.1 Field Type: 1703
    /// - JSON Field Name: `transaction_id`
    let transactionID: TransactionID
    
    /// The transaction identifier of the original purchase.
    /// - ASN.1 Field Type: 1705
    /// - JSON Field Name: `original_transaction_id`
    let originalTransactionID: OriginalTransactionID
    
    /// In an auto-renewable subscription receipt, the purchase date is the
    /// date when the subscription was either purchased or renewed (with or without a lapse).
    /// For an automatic renewal that occurs on the expiration date of the current period,
    /// the purchase date is the start date of the next period, which is identical to the
    /// end date of the current period.
    /// - ASN.1 Field Type: 1704
    /// - JSON Field Name: `purchase_date`
    let purchaseDate: Date
    
    /// Subscription's expiry date.
    /// - ASN.1 Field Type: 1708
    /// - JSON Field Name: `expires_date`
    let expires: Date
    
    /// For an auto-renewable subscription, whether or not it is in the introductory price period.
    /// - ASN.1 Field Type: 1719
    /// - JSON Field Name: `is_in_intro_offer_period`
    let isInIntroOfferPeriod: Bool
    
    /// Whether a pervious subscription in the receipt has the value true for `is_in_intro_offer_period`.
    /// This field is calculated from the receipt.
    let hasBeenInIntroOfferPeriod: Bool
    
    /// Returns true if given current time, the subscription is almost expired with a granularity of a minute.
    func isApproximatelyExpired(
        getCurrentTime: () -> Date,
        compareDates: (Date, Date, Calendar.Component) -> ComparisonResult
    ) -> Bool {
        switch compareDates(getCurrentTime(), expires, .minute) {
        case .orderedAscending: return false
        case .orderedDescending: return true
        case .orderedSame: return true
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.transactionID == rhs.transactionID
    }
    
    func hash(into hasher: inout Hasher) {
        // Transaction ID is unique.
        hasher.combine(self.transactionID)
    }
}

extension Set where Element == SubscriptionIAPPurchase {
    
    func sortedByExpiry() -> [Element] {
        self.sorted {
            $0.expires < $1.expires
        }
    }
    
}
