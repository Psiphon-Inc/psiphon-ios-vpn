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


struct StoreProductIds {
    let ids: Set<String>

    private enum ProductIdType: String {
        case subscription = "subscriptionProductIds"
        case psiCash = "psiCashProductIds"
    }

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

