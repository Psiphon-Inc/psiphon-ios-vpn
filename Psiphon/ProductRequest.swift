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

struct PsiCashAppStoreProductsState: Equatable {
    var psiCashProducts: PendingWithLastSuccess<[PsiCashPurchasableViewModel], SystemErrorEvent>
    
    /// Strong reference to request object.
    /// - Reference: https://developer.apple.com/documentation/storekit/skproductsrequest
    var psiCashRequest: SKProductsRequest?
}

extension PsiCashAppStoreProductsState {
    init() {
        psiCashProducts = .completed(.success([]))
        psiCashRequest = nil
    }
}

enum ProductRequestAction {
    case getProductList
    case productRequestResult(SKProductsRequest, Result<SKProductsResponse, SystemErrorEvent>)
}

typealias ProductRequestEnvironment = ProductRequestDelegate

func productRequestReducer(
    state: inout PsiCashAppStoreProductsState, action: ProductRequestAction,
    environment: ProductRequestEnvironment
) -> [Effect<ProductRequestAction>] {
    switch action {
    case .getProductList:
        guard case .completed(_) = state.psiCashProducts else {
            return []
        }
        // If previous value had successful reslut,
        // then the success value is added to `.pending` case.
        state.psiCashProducts = .pending(previousValue: state.psiCashProducts)
        
        let request = SKProductsRequest(productIdentifiers: StoreProductIds.psiCash().values)
        state.psiCashRequest = request
        return [
            .fireAndForget {
                request.delegate = environment
                request.start()
            }
        ]
        
    case let .productRequestResult(request, result):
        guard request == state.psiCashRequest else {
            fatalError()
        }
        state.psiCashRequest = nil
        state.psiCashProducts = .completed(
            result.map { response in
                response.products.compactMap { (skProduct) -> PsiCashPurchasableViewModel? in
                    guard let product = try? AppStoreProduct(skProduct) else {
                        return nil
                    }
                    return PsiCashPurchasableViewModel.from(product)
                    
                }
            }
        )
        return []
    }
}

final class ProductRequestDelegate: StoreDelegate<ProductRequestAction>, SKProductsRequestDelegate {
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        sendOnMain(.productRequestResult(request, .success(response)))
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        sendOnMain(
            .productRequestResult(
                request as! SKProductsRequest, .failure(SystemErrorEvent(error as SystemError))
            )
        )
    }
    
}

