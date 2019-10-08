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


/// Delegate for StoreKit product request object:`SKProductsRequest`.
class ProductRequest: PromiseDelegate<Result<[SKProduct], Error>>,
SKProductsRequestDelegate {

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        promise.fulfill(.success(response.products))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        promise.fulfill(.failure(error))
    }

    /// Sends a product request to StoreKit for the provided product ids.
    /// - Note: caller must hold a strong reference to the returned `ProductRequest` object.
    static func request(for storeProductIds: StoreProductIds) -> ProductRequest {
        let responseDelegate = ProductRequest()
        let request = SKProductsRequest(productIdentifiers: storeProductIds.ids)
        request.delegate = responseDelegate
        request.start()
        return responseDelegate
    }

}

enum ProductIdError: Error {
    case invalidString(String)
}

enum ProductIdType: String {
    case subscription = "subscriptionProductIds"
    case psiCash = "psiCashProductIds"

    static func type(of transaction: SKPaymentTransaction) throws -> ProductIdType {
        guard let txIdentifier = transaction.transactionIdentifier else {
            fatalError("transaction has no identifier: '\(String(describing: transaction))'")
        }

        if txIdentifier.hasPrefix("ca.psiphon.Psiphon.psicash.") {
            return .psiCash
        }

        if txIdentifier.hasPrefix("ca.psiphon.Psiphon.") {
            return .subscription
        }

        throw ProductIdError.invalidString(txIdentifier)
    }
}

struct StoreProductIds {
    let ids: Set<String>

    private init(for type: ProductIdType, validator: (Set<String>) -> Bool) {
        ids = try! plistReader(key: type.rawValue)

    }

    static func subscription() -> StoreProductIds {
        return .init(for: .subscription) { ids -> Bool in
            // TODO! do some validation here.
            return true
        }
    }

    static func psiCash() -> StoreProductIds {
        return .init(for: .psiCash) { ids -> Bool in
            // TODO! do some validation here.
            return true
        }
    }
}

struct ReceiptData: Equatable, Codable {
    let fileSize: Int

    /// Subscription data stored in the receipt.
    /// Nil if no subscription data is found in the receipt.
    let subscription: SubscriptionData?
    // TODO! add consumables here
    // let consumable: Array<Something>

    /// Parses local app receipt and returns a `RceiptData` object.
    /// If no receipt file is found at path pointed to by the `Bundle` `.none` is returned.
    /// - Note: It is expected for the `Bundle` object to have a valid
    static func fromLocalReceipt(_ appBundle: Bundle) -> ReceiptData? {

        // TODO!! what are the cases where this is nil?
        let receiptURL = appBundle.appStoreReceiptURL!
        let appBundleIdentifier = appBundle.bundleIdentifier!

        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            // TODO!! do something? receipt file doesn't exist. Why was this function called at all?
            return .none
        }
        guard let receiptData = AppStoreReceiptData.parseReceipt(receiptURL) else {
            // TODO!! maybe do something if the parsing fails.
            return .none
        }
        // Validate bundle identifier.
        guard receiptData.bundleIdentifier == appBundleIdentifier else {
            // TODO!! maybe do something if the bundle identifiers don't match
            return .none
        }
        guard let inAppSubscription = receiptData.inAppSubscriptions else {
            return .none
        }
        guard let castedInAppSubscription = inAppSubscription as? [String: Any] else {
            return .none
        }

        let subscriptionData =
            SubscriptionData.fromSubsriptionDictionary(castedInAppSubscription)

        return ReceiptData(fileSize: receiptData.fileSize as! Int,
                           subscription: subscriptionData)
    }

}

// TODO! store and recover this struct instead of the subscription dictionary
struct SubscriptionData: Equatable, Codable {
    let latestExpiry: Date
    let productId: String
    let hasBeenInIntroPeriod: Bool

    // Enum values match dictionary keys defined in "IAPStoreHelper.h"
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
