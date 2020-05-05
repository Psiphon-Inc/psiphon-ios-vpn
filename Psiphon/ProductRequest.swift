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


/// Parsed representation of AppStore PsiCash consumable product.
enum ParsedPsiCashAppStorePurchasable: Equatable {
    
    // Map from App Store defined Product Id to PsiCash value.
    static let supportedProducts: [String: Double] = [
        "ca.psiphon.Psiphon.psicash_1000": 1000,
        "ca.psiphon.Psiphon.psicash_4000": 4000,
        "ca.psiphon.Psiphon.psicash_10000": 10000,
        "ca.psiphon.Psiphon.psicash_30000": 30000,
        "ca.psiphon.Psiphon.psicash_100000": 100000,
    ]
    
    
    case purchasable(PsiCashPurchasableViewModel)
    case parseError(reason: String)
}

extension ParsedPsiCashAppStorePurchasable {
    
    var viewModel: PsiCashPurchasableViewModel? {
        guard case let .purchasable(value) = self else {
            return nil
        }
        return value
    }
    
    static func make(product: AppStoreProduct, formatter: PsiCashAmountFormatter) -> Self {
        let productIdentifier = product.skProduct.productIdentifier
        guard let psiCashValue = Self.supportedProducts[productIdentifier] else {
            return .parseError(reason: """
                AppStore IAP product with identifier '\(productIdentifier)' is not a supported product
                """)
        }
        guard let title = formatter.string(from: psiCashValue) else {
            return .parseError(reason: "Failed to format '\(psiCashValue)' into string")
        }
        return .purchasable(.init(product: .product(product),
                                  title: title,
                                  subtitle: product.skProduct.localizedDescription,
                                  price: product.skProduct.price.doubleValue))
    }
    
}

extension Array where Element == ParsedPsiCashAppStorePurchasable {
    
    func sortPurchasables() -> [Element] {
        self.sorted { (first, second) -> Bool in
            guard case let .purchasable(firstPurchasable) = first else {
                return false
            }
            guard case let .purchasable(secondPurchasable) = second else {
                return true
            }
            return firstPurchasable.price < secondPurchasable.price
        }
    }
    
}

struct PsiCashAppStoreProductsState: Equatable {
    
    var psiCashProducts:
        PendingWithLastSuccess<[ParsedPsiCashAppStorePurchasable], SystemErrorEvent>
    
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

typealias ProductRequestEnvironment = (
    productRequestDelegate: ProductRequestDelegate,
    supportedPsiCashIAPProductIDs: SupportedAppStoreProductIDs
)

func productRequestReducer(
    state: inout PsiCashAppStoreProductsState, action: ProductRequestAction,
    environment: ProductRequestEnvironment
) -> [Effect<ProductRequestAction>] {
    switch action {
    case .getProductList:
        guard case .completed(_) = state.psiCashProducts else {
            return []
        }
        // If previous value had successful result,
        // then the success value is added to `.pending` case.
        state.psiCashProducts = .pending(previousValue: state.psiCashProducts)
        
        let request = SKProductsRequest(productIdentifiers: environment.supportedPsiCashIAPProductIDs.values)
        state.psiCashRequest = request
        return [
            .fireAndForget {
                request.delegate = environment.productRequestDelegate
                request.start()
            }
        ]
        
    case let .productRequestResult(request, result):
        guard request == state.psiCashRequest else {
            fatalErrorFeedbackLog("""
                Expected SKProductRequest object '\(request)' to match
                state reference '\(String(describing: state.psiCashRequest))'.
                """)
        }
        state.psiCashRequest = nil
        
        var effects = [Effect<ProductRequestAction>]()
        
        // Logs invalid Product IDs/error.
        switch result {
        case let .success(skProductsResponse):
            effects += skProductsResponse.invalidProductIdentifiers.map { invalidProductID in
                feedbackLog(.warn, tag: "PsiCashProductRequest",
                            "Invalid App Store IAP Product ID: '\(invalidProductID)'"
                ).mapNever()
            }
        case let .failure(errorEvent):
            effects.append(
                feedbackLog(.error, errorEvent).mapNever()
            )
        }
        
        state.psiCashProducts = .completed(
            result.map { response in
                
                let formatter = PsiCashAmountFormatter(locale: Locale.current)

                return response.products.map { skProduct -> ParsedPsiCashAppStorePurchasable in
                    do {
                        let product = try AppStoreProduct(skProduct)
                        return .make(product: product, formatter: formatter)
                    } catch {
                        return .parseError(reason: String(describing: error))
                    }
                }.sortPurchasables()
            }
        )
        
        return effects
    }
}

final class ProductRequestDelegate: StoreDelegate<ProductRequestAction>, SKProductsRequestDelegate {
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        storeSend(.productRequestResult(request, .success(response)))
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        storeSend(
            .productRequestResult(
                request as! SKProductsRequest, .failure(SystemErrorEvent(error as SystemError))
            )
        )
    }
    
}

