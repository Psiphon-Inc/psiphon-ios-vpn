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

// TODO: Double check reference chain
func appStoreProductRequest(
    productIds: StoreProductIds
) -> Effect<Result<[SKProduct], SystemErrorEvent>> {

    return .promise { lifetime -> Promise<Result<[SKProduct], SystemErrorEvent>> in
        var request: ProductRequest? = ProductRequest.request(storeProductIds: productIds)
        lifetime += AnyDisposable {
            request = nil
        }
        return request!.promise
    }
}

/// Delegate for StoreKit product request object:`SKProductsRequest`.
class ProductRequest: PromiseDelegate<Result<[SKProduct], SystemErrorEvent>>, SKProductsRequestDelegate {

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        promise.fulfill(.success(response.products))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        promise.fulfill(.failure(SystemErrorEvent(error as NSError)))
    }

    /// Sends a product request to StoreKit for the provided product ids.
    /// - Note: caller must hold a strong reference to the returned `ProductRequest` object.
    static func request(storeProductIds: StoreProductIds) -> ProductRequest {
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

struct AppStoreProduct {
    let type: AppStoreProductType
    let skProduct: SKProduct

    init?(_ skProduct: SKProduct) {
        guard let type = try? AppStoreProductType.from(skProduct: skProduct) else {
            return nil
        }
        self.type = type
        self.skProduct = skProduct
    }
}

enum AppStoreProductType: String {
    case subscription = "subscriptionProductIds"
    case psiCash = "psiCashProductIds"

    private static func from(productIdentifier: String) throws -> AppStoreProductType {
        if productIdentifier.hasPrefix("ca.psiphon.Psiphon.psicash.") {
            return .psiCash
        }

        if productIdentifier.hasPrefix("ca.psiphon.Psiphon.") {
            return .subscription
        }

        throw ProductIdError.invalidString(productIdentifier)
    }

    static func from(transaction: SKPaymentTransaction) throws -> AppStoreProductType {
        return try from(productIdentifier: transaction.payment.productIdentifier)
    }

    static func from(skProduct: SKProduct) throws -> AppStoreProductType {
        return try from(productIdentifier: skProduct.productIdentifier)
    }
}

struct StoreProductIds {
    let ids: Set<String>

    private init(for type: AppStoreProductType, validator: (Set<String>) -> Bool) {
        ids = try! plistReader(key: type.rawValue)
    }

    static func subscription() -> StoreProductIds {
        return .init(for: .subscription) { ids -> Bool in
            // TODO: do some validation here.
            return true
        }
    }

    static func psiCash() -> StoreProductIds {
        return .init(for: .psiCash) { ids -> Bool in
            // TODO: do some validation here.
            return true
        }
    }
}

struct AppStoreReceipt: Equatable, Codable {
    let fileSize: Int
    /// Subscription data stored in the receipt.
    /// Nil if no subscription data is found in the receipt.
    let subscription: SubscriptionData?
    let data: Data

    /// Parses local app receipt and returns a `RceiptData` object.
    /// If no receipt file is found at path pointed to by the `Bundle` `.none` is returned.
    /// - Note: It is expected for the `Bundle` object to have a valid
    static func fromLocalReceipt(_ appBundle: PsiphonBundle) -> AppStoreReceipt? {
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

        return AppStoreReceipt(fileSize: receiptData.fileSize as! Int,
                           subscription: subscriptionData,
                           data: data)
    }

}

// TODO! store and recover this struct instead of the subscription dictionary
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

enum IAPPendingTransactionState: Equatable {
    case purchasing
    case deferred
}

enum IAPCompletedTransactionState: Equatable {
    case purchased
    case restored
}

enum IAPTransactionState: Equatable {
    case pending(IAPPendingTransactionState)
    case completed(Result<IAPCompletedTransactionState, SystemError>)
}

extension SKPaymentTransaction {

    /// Stricter typing of transaction state type `SKPaymentTransactionState`.
    var typedTransactionState: IAPTransactionState {
        switch self.transactionState {
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
            let error = self.error! as SystemError
            return .completed(.failure(error))
        @unknown default:
            fatalError("unknown transaction state \(self.transactionState)")
        }
    }

    /// Indicates whether the app receipt has been updated.
    var appReceiptUpdated: Bool {
        // Each case is explicitely typed as returning true or false
        // to ensure function correctness in future updates.
        switch self.typedTransactionState {
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

extension Array where Element == SKPaymentTransaction {

    var appReceiptUpdated: Bool {
        return self.map({ $0.appReceiptUpdated }).contains(true)
    }

}
