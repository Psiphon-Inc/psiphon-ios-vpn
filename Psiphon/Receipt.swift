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

struct ReceiptData: Equatable, Codable {
    let fileSize: Int
    /// Subscription data stored in the receipt.
    /// Nil if no subscription data is found in the receipt.
    let subscription: SubscriptionData?
    let data: Data
    
    /// Parses local app receipt and returns a `RceiptData` object.
    /// If no receipt file is found at path pointed to by the `Bundle` `.none` is returned.
    /// - Note: It is expected for the `Bundle` object to have a valid
    static func fromLocalReceipt(_ appBundle: PsiphonBundle) -> ReceiptData? {
        let receiptURL = appBundle.appStoreReceiptURL
        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            return .none
        }
        guard let receiptData = AppStoreReceiptData.parseReceipt(receiptURL) else {
            PsiFeedbackLogger.error(withType: "InAppPurchase", message: "parse failed",
                                    object: FatalError(message: "failed to parse app receipt"))
            return .none
        }
        // Validate bundle identifier.
        guard receiptData.bundleIdentifier == appBundle.bundleIdentifier else {
            fatalError("""
                Receipt bundle identifier '\(String(describing: receiptData.bundleIdentifier))'
                does not match app bundle identifier '\(appBundle.bundleIdentifier)'
                """)
        }
        guard let inAppSubscription = receiptData.inAppSubscriptions else {
            return .none
        }
        guard let castedInAppSubscription = inAppSubscription as? [String: Any] else {
            return .none
        }
        
        let subscriptionData =
            SubscriptionData.fromSubsriptionDictionary(castedInAppSubscription)
        
        let data: Data
        do {
            try data = Data(contentsOf: receiptURL)
        } catch {
            PsiFeedbackLogger.error(withType: "InAppPurchase",
                                    message: "failed to read app receipt",
                                    object: error)
            return .none
        }
        
        return ReceiptData(fileSize: receiptData.fileSize as! Int,
                       subscription: subscriptionData,
                       data: data)
    }
    
}


struct SubscriptionData: Equatable, Codable {
    let latestExpiry: Date
    let productId: String
    let hasBeenInIntroPeriod: Bool

    // Enum values match dictionary keys defined in "AppStoreReceiptData.h"
    private enum ReceiptFields: String {
        case appReceiptFileSize = "app_receipt_file_size"
        case latestExpirationDate = "latest_expiration_date"
        case productId = "product_id"
        case hasBeenInIntroPeriod = "has_been_in_intro_period"
    }

    static func fromSubsriptionDictionary(_ dict: [String: Any]) -> SubscriptionData? {
        guard let expiration = dict[ReceiptFields.latestExpirationDate] as? Date else {
            return .none
        }
        guard let productId = dict[ReceiptFields.productId] as? String else {
            return .none
        }
        guard let introPeriod = dict[ReceiptFields.hasBeenInIntroPeriod] as? Bool else {
            return .none
        }
        return SubscriptionData(latestExpiry: expiration, productId: productId,
                                hasBeenInIntroPeriod: introPeriod)
    }
}
