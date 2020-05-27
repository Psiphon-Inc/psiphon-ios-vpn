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
    
}
