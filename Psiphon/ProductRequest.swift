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
import PsiApi
import AppStoreIAP

/// Parsed representation of AppStore PsiCash consumable product.
enum ParsedPsiCashAppStorePurchasable: Equatable {
    
    // Map from App Store defined Product Id to PsiCash value.
    static let supportedProducts: [String: Double] = [
        "ca.psiphon.Psiphon.Consumable.PsiCash.1000": 1000,
        "ca.psiphon.Psiphon.Consumable.PsiCash.4000": 4000,
        "ca.psiphon.Psiphon.Consumable.PsiCash.10000": 10000,
        "ca.psiphon.Psiphon.Consumable.PsiCash.30000": 30000,
        "ca.psiphon.Psiphon.Consumable.PsiCash.100000": 100000,
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
        guard let psiCashValue = Self.supportedProducts[product.productID] else {
            return .parseError(reason: """
                AppStore IAP product with identifier '\(product.productID)' is not a supported product
                """)
        }
        guard let title = formatter.string(from: psiCashValue) else {
            return .parseError(reason: "Failed to format '\(psiCashValue)' into string")
        }
        return .purchasable(
            PsiCashPurchasableViewModel(
                product: .product(product),
                title: title,
                subtitle: product.localizedDescription,
                localizedPrice: product.price,
                clearedForSale: true
            )
        )
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
                        
            switch (firstPurchasable.localizedPrice, secondPurchasable.localizedPrice) {
            case (.free, .free):
                return true
            case (.free, .localizedPrice(price: _, priceLocale: _)):
                return true
            case (.localizedPrice(price: _, priceLocale: _), .free):
                return false
            case let (.localizedPrice(price: price1, priceLocale: priceLocale1),
                      .localizedPrice(price: price2, priceLocale: priceLocale2)):
                switch priceLocale1.currencyCode.compare(priceLocale2.currencyCode) {
                case .orderedSame:
                    return price1 < price2
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                }
            }
            
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
    feedbackLogger: FeedbackLogger,
    productRequestDelegate: ProductRequestDelegate,
    supportedAppStoreProducts: SupportedAppStoreProducts
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
        
        let maybeRequestingProductIDs = environment.supportedAppStoreProducts.supported[.psiCash]
        guard let requestingProductIDs = maybeRequestingProductIDs else {
            environment.feedbackLogger.fatalError("PsiCash product not supported")
            return []
        }
        
        let request = SKProductsRequest(productIdentifiers: requestingProductIDs.rawValues)
        state.psiCashRequest = request
        
        return [
            .fireAndForget {
                request.delegate = environment.productRequestDelegate
                request.start()
            },
            environment.feedbackLogger.log(.info, tag: "PsiCashProductRequest",
                        "Requesting product IDs: '\(requestingProductIDs)'").mapNever()
        ]
        
    case let .productRequestResult(request, result):
        guard request == state.psiCashRequest else {
            environment.feedbackLogger.fatalError("""
                Expected SKProductRequest object '\(request)' to match
                state reference '\(String(describing: state.psiCashRequest))'.
                """)
            return []
        }
        state.psiCashRequest = nil
        
        var effects = [Effect<ProductRequestAction>]()
        
        // Logs invalid Product IDs/error.
        switch result {
        case let .success(skProductsResponse):
            effects += skProductsResponse.invalidProductIdentifiers.map { invalidProductID in
                environment.feedbackLogger.log(.warn, tag: "PsiCashProductRequest",
                            "Invalid App Store IAP Product ID: '\(invalidProductID)'"
                ).mapNever()
            }
        case let .failure(errorEvent):
            effects.append(
                environment.feedbackLogger.log(.error, errorEvent).mapNever()
            )
        }
        
        state.psiCashProducts = .completed(
            result.map { response in
                
                let formatter = PsiCashAmountFormatter(locale: Locale.current)

                return response.products.map { skProduct -> ParsedPsiCashAppStorePurchasable in
                    do {
                        let product = try AppStoreProduct.from(
                            skProduct: skProduct,
                            isSupportedProduct: environment.supportedAppStoreProducts
                                .isSupportedProduct(_:)
                        )
                        guard case .psiCash = product.type else {
                            throw ErrorRepr(repr: "Expected PsiCash product")
                        }
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
                request as! SKProductsRequest, .failure(SystemErrorEvent(SystemError(error)))
            )
        )
    }
    
}

