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
import AppStoreIAP

extension ReceiptData {
    
    /// Parses local app receipt and returns a `ReceiptData` object.
    /// If no receipt file is found at path pointed to by the `Bundle` `.none` is returned.
    /// - Note: It is expected for the `Bundle` object to have a valid
    static func parseLocalReceipt(
        appBundle: PsiphonBundle,
        isSupportedProduct: (ProductID) -> AppStoreProductType?,
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
            let productID = ProductID(rawValue: $0.productIdentifier)!
            return isSupportedProduct(productID) == .subscription
        }.map {
            $0.isInIntroPeriod
        }.contains(true)

        // Filters out subscription purchases that have already expired at by `readDate`.
        let subscriptionPurchases = Set(parsedData.inAppPurchases
            .compactMap { parsedIAP -> SubscriptionIAPPurchase? in
                let productID = ProductID(rawValue: parsedIAP.productIdentifier)!
                guard case .subscription = isSupportedProduct(productID) else {
                    return nil
                }
                let purchase = SubscriptionIAPPurchase(
                    productID: productID,
                    transactionID: TransactionID(rawValue: parsedIAP.transactionID)!,
                    originalTransactionID: OriginalTransactionID(rawValue:
                        parsedIAP.originalTransactionID)!,
                    webOrderLineItemID: WebOrderLineItemID(rawValue:
                        parsedIAP.webOrderLineItemID!)!,
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
                let productID = ProductID(rawValue: parsedIAP.productIdentifier)!
                guard isSupportedProduct(productID)?.isConsumable ?? false else {
                    return nil
                }
                return ConsumableIAPPurchase(
                    productID: productID,
                    transactionID: TransactionID(rawValue: parsedIAP.transactionID)!,
                    purchaseDate: parsedIAP.purchaseDate
                )
        })
                
        return ReceiptData(filename: receiptURL.lastPathComponent,
                           subscriptionInAppPurchases: subscriptionPurchases,
                           consumableInAppPurchases: consumablePurchases,
                           data: data, readDate: readDate)
    }
    
}
