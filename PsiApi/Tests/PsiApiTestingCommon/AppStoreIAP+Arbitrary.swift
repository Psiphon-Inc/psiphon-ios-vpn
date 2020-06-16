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
import ReactiveSwift
import PsiCashClient
import Testing
import StoreKit
import SwiftCheck
import Utilities
@testable import PsiApi
@testable import AppStoreIAP

extension PsiCashAmount: Arbitrary {
    public static var arbitrary: Gen<PsiCashAmount> {
        Int64.arbitrary.resize(1000).map {PsiCashAmount.init(nanoPsi: abs($0)) }
    }
}

extension SpeedBoostProduct: Arbitrary {
    public static var arbitrary: Gen<SpeedBoostProduct> {
        Gen<String>.fromElements(of: Set(SpeedBoostProduct.supportedProducts.keys)).map {
            SpeedBoostProduct(distinguisher: $0)!
        }
    }
}

extension PsiCashPurchasable: Arbitrary where Product == SpeedBoostProduct {
    public static var arbitrary: Gen<PsiCashPurchasable<SpeedBoostProduct>> {
        Gen.zip(SpeedBoostProduct.arbitrary, PsiCashAmount.arbitrary)
            .map(PsiCashPurchasable.init(product: price:))
    }
}

extension Authorization.AccessType: Arbitrary {
    public static var arbitrary: Gen<Authorization.AccessType> {
        Gen.fromElements(of: Authorization.AccessType.allCases)
    }
}

extension Authorization: Arbitrary {
    public static var arbitrary: Gen<Authorization> {
        Gen.zip(AuthorizationID.arbitrary, AccessType.arbitrary, Date.arbitrary)
            .map(Authorization.init(id:accessType:expires:))
    }
}

extension SignedAuthorization: Arbitrary {
    public static var arbitrary: Gen<SignedAuthorization> {
        Gen.zip(Authorization.arbitrary, String.arbitrary, String.arbitrary)
            .map(SignedAuthorization.init(authorization:signingKeyID:signature:))
    }
}

extension SignedData: Arbitrary where Decoded == SignedAuthorization {
    public static var arbitrary: Gen<SignedData<SignedAuthorization>> {
        // Note: in the future, likely for different reducers, this could be broken
        // out into a separate function where the frequencies can be configured.
        Gen.frequency([
            // Raw data and authorization match
            (3,
             SignedAuthorization.arbitrary.map{
                let encoder = JSONEncoder.makeRfc3339Encoder()
                let data = try! encoder.encode($0)
                return SignedData(rawData:data.base64EncodedString(), decoded:$0)
            }),
            // Raw data and authorization mismatch
            (1,
             Gen.zip(String.arbitrary, SignedAuthorization.arbitrary)
                .map(SignedData.init(rawData:decoded:))),
        ])
    }
}

extension ExpirableTransaction: Arbitrary {
    public static var arbitrary: Gen<ExpirableTransaction> {
        Gen.zip(String.arbitrary, Date.arbitrary, Double.arbitrary.resize(10), SignedData.arbitrary)
            .map {
                // Applies small time drift in the order of 10s of seconds ($2)
                // to generated server time ($1).
                ExpirableTransaction(transactionId: $0, serverTimeExpiry: $1,
                                     localTimeExpiry: $1 + $2, authorization: $3)
        }
    }
}

extension PurchasedExpirableProduct: Arbitrary where Product == SpeedBoostProduct {
    public static var arbitrary: Gen<PurchasedExpirableProduct<SpeedBoostProduct>> {
        Gen.zip(ExpirableTransaction.arbitrary, SpeedBoostProduct.arbitrary)
            .map(PurchasedExpirableProduct.init(transaction:product:))
    }
}

extension PsiCashPurchasedType: Arbitrary {
    public static var arbitrary: Gen<PsiCashPurchasedType> {
        Gen.one(of: [
            // Should cover all cases.
            PurchasedExpirableProduct<SpeedBoostProduct>.arbitrary
                .map(PsiCashPurchasedType.speedBoost)
        ])
    }
}

extension PsiCashPurchasableType: Arbitrary {
    public static var arbitrary: Gen<PsiCashPurchasableType> {
        Gen.one(of: [
            // Should cover all cases.
            PsiCashPurchasable<SpeedBoostProduct>.arbitrary
                .map(PsiCashPurchasableType.speedBoost)
        ])
    }
}

extension PsiCashParseError: Arbitrary {
    public static var arbitrary: Gen<PsiCashParseError> {
        Gen.fromElements(of: [
            // Should cover all cases.
            PsiCashParseError.speedBoostParseFailure(message:"Failed to parse")
        ])
    }
}

extension PsiCashParsed: Arbitrary where Value: Arbitrary {
    public static var arbitrary: Gen<PsiCashParsed<Value>> {
        Gen.zip(Value.arbitrary.proliferate, PsiCashParseError.arbitrary.proliferate)
            .map(PsiCashParsed.init(items:parseErrors:))
    }
}

extension PsiCashAuthPackage: Arbitrary {
    public static var arbitrary: Gen<PsiCashAuthPackage> {
        Gen.weighted([
            (1, PsiCashAuthPackage(withTokenTypes: [])),
            (3, PsiCashAuthPackage.completeAuthPackage),
        ])
    }
    
    public static let completeAuthPackage = PsiCashAuthPackage(withTokenTypes:
        ["earner", "indicator", "spender"])
}

extension PsiCashLibData: Arbitrary {
    /// Leans 9/10 times towards producing a non-empty `PsiCashLibData` value.
    /// 1/10 times generates `PsiCashLibData()` with default initializer.
    public static var arbitrary: Gen<PsiCashLibData> {
        Gen<Bool>.weighted([
            // The weights are chosen more of less arbitrarily.
            (1, false),
            (9, true)
        ]).flatMap { hasPsiCash in
            // Uses generated bool values to determine availability of PsiCash.
            if hasPsiCash {
                return Gen.zip(
                    Gen.pure(PsiCashAuthPackage.completeAuthPackage),
                    PsiCashAmount.arbitrary,
                    PsiCashParsed<PsiCashPurchasableType>.arbitrary,
                    PsiCashParsed<PsiCashPurchasedType>.arbitrary
                ).map(PsiCashLibData.init(authPackage:balance:availableProducts:activePurchases:))
            } else {
                return Gen.pure(PsiCashLibData())
            }
        }
    }
}

extension PaymentTransaction.TransactionState.PendingTransactionState: Arbitrary {
    public static var arbitrary: Gen<PaymentTransaction.TransactionState.PendingTransactionState> {
        Gen.fromElements(of: [
            // Should cover all cases.
            .purchasing,
            .deferred,
        ])
    }
}

extension PaymentTransaction.TransactionState.CompletedTransactionState: Arbitrary {
    public static var arbitrary: Gen<PaymentTransaction.TransactionState.CompletedTransactionState> {
        Gen.fromElements(of: [
            // Should cover all cases
            .purchased,
            .restored,
        ])
    }
}

extension PaymentTransaction.TransactionState: Arbitrary {
    public static var arbitrary: Gen<PaymentTransaction.TransactionState> {
        Gen.one(of: [
            // Should cover all cases
            PendingTransactionState.arbitrary
                .map(PaymentTransaction.TransactionState.pending),
            
            Result<Pair<Date, CompletedTransactionState>, Either<SystemError, SKError>>.arbitrary
                .map(PaymentTransaction.TransactionState.completed)
        ])
    }
}

extension TransactionID: Arbitrary {
    public static var arbitrary: Gen<TransactionID> {
        Int.arbitrary.resize(999_999_999).map {
            TransactionID.init(rawValue: String(abs($0)))!
        }
    }
}

extension OriginalTransactionID: Arbitrary {
    public static var arbitrary: Gen<OriginalTransactionID> {
        Int.arbitrary.resize(999_999_999).map {
            OriginalTransactionID.init(rawValue: String(abs($0)))!
        }
    }
}

extension WebOrderLineItemID: Arbitrary {
    public static var arbitrary: Gen<WebOrderLineItemID> {
        Int.arbitrary.resize(999_999_999).map {
            WebOrderLineItemID.init(rawValue: String(abs($0)))!
        }
    }
}


extension Payment: Arbitrary {
    public static var arbitrary: Gen<Payment> {
        Gen.compose { c in
            Payment(productID: c.generate())
        }
    }
}

extension PaymentTransaction: Arbitrary {
    public static var arbitrary: Gen<PaymentTransaction> {
        Gen.compose { c in
            let transactionID: TransactionID = c.generate()
            let productID: ProductID = c.generate()
            let transactionState: TransactionState = c.generate()
            let payment: Payment = c.generate(using:
                Gen.pure(productID).map({Payment.init(productID: $0)})
            )
            
            return PaymentTransaction(
                transactionID: { transactionID },
                productID: { productID },
                transactionState: { transactionState },
                payment: { payment },
                isEqual: { $0.transactionID() == transactionID },
                skPaymentTransaction: { nil }
            )
        }
    }
}

extension UnfinishedConsumableTransaction.VerificationRequestState: Arbitrary {
    public static var arbitrary: Gen<UnfinishedConsumableTransaction.VerificationRequestState> {
        Gen.one(of: [
            // Should cover all cases
            Gen.pure(.notRequested),
            Gen.pure(.pendingResponse),
            ErrorEvent<ErrorRepr>.arbitrary
                .map(UnfinishedConsumableTransaction.VerificationRequestState.requestError),
        ])
    }
}

extension UnfinishedConsumableTransaction: Arbitrary {
    public static var arbitrary: Gen<UnfinishedConsumableTransaction> {
        Gen.zip(PaymentTransaction.arbitrary, VerificationRequestState.arbitrary)
            .suchThat({ (paymentTransaction, _) -> Bool in
                if case .completed(.success(_)) = paymentTransaction.transactionState() {
                    return true
                }
                return false
            }).map {
                guard let value =
                    UnfinishedConsumableTransaction(transaction: $0, verificationState: $1) else {
                        XCTFatal()
                }
                return value
        }
    }
}

extension AppStoreProductType: Arbitrary {
    public static var arbitrary: Gen<AppStoreProductType> {
        Gen.fromElements(of: AppStoreProductType.allCases)
    }
}

extension LocalizedPrice: Arbitrary {
    public static var arbitrary: Gen<LocalizedPrice> {
        Gen.one(of: [
            // Should cover all cases
            Gen.pure(LocalizedPrice.free),
            Gen.zip(positiveDouble(), Locale.arbitrary)
                .map(LocalizedPrice.localizedPrice(price: priceLocale:))
        ])
    }
}

extension AppStoreProduct: Arbitrary {
    public static var arbitrary: Gen<AppStoreProduct> {
        Gen.compose { c in
            AppStoreProduct(
                type: c.generate(),
                productID: c.generate(),
                localizedDescription: c.generate(),
                price: c.generate(),
                skProductRef: nil
            )
        }
    }
    
    static var arbitraryPsiCashProduct: Gen<AppStoreProduct> {
        Gen.compose { c in
            AppStoreProduct(
                type: .psiCash,
                productID: c.generate(),
                localizedDescription: c.generate(),
                price: c.generate(),
                skProductRef: nil
            )
        }
    }
    
}

extension IAPError: Arbitrary {
    public static var arbitrary: Gen<IAPError> {
        Gen.one(of: [
            // Should cover all cases
            String.arbitrary.map(IAPError.failedToCreatePurchase(reason:)),
            IAPError.StoreKitError.arbitrary.map(IAPError.storeKitError)
        ])
    }
}

extension IAPPurchasing: Arbitrary {
    public static var arbitrary: Gen<IAPPurchasing> {
        Gen.compose { c in
            let product: AppStoreProduct = c.generate()
            
            return IAPPurchasing(productType: product.type,
                                 productID: product.productID,
                                 purchasingState: c.generate())
        }
    }
    
    /// Generates `IAPPurchasing` satisfying following condition:
    ///
    /// ```
    /// purchasingState == .pending(.none) ||
    ///   purchasingState == .pending(.some(_))
    /// ```
    ///
    static var arbitraryWithPending: Gen<IAPPurchasing> {
        Gen.compose { c in
            let product: AppStoreProduct = c.generate()
            let payment: Payment? = c.generate()
            
            return IAPPurchasing(productType: product.type,
                                 productID: product.productID,
                                 purchasingState: .pending(payment))
        }
    }
    
    static var arbitraryWithPendingNoPayment: Gen<IAPPurchasing> {
        Gen.compose { c in
            let product: AppStoreProduct = c.generate()
            
            return IAPPurchasing(productType: product.type,
                                 productID: product.productID,
                                 purchasingState: .pending(nil))
        }
    }
    
}

extension IAPState: Arbitrary {
    public static var arbitrary: Gen<IAPState> {
        Gen.compose { c in
            IAPState(unverifiedPsiCashTx: c.generate(),
                     purchasing: c.generate(using:
                        [AppStoreProductType: IAPPurchasing].arbitrary
                            .suchThat({ dict -> Bool in
                                // The productType of the given key's value should
                                // match the key.
                                for key in dict.keys {
                                    if dict[key]?.productType != key {
                                        return false
                                    }
                                }
                                return true
                            })
            ))
        }
    }
}

extension PsiCashBalance.BalanceIncreaseExpectationReason: Arbitrary {
    public static var arbitrary: Gen<PsiCashBalance.BalanceIncreaseExpectationReason> {
        Gen.fromElements(of: PsiCashBalance.BalanceIncreaseExpectationReason.allCases)
    }
}

extension PsiCashBalance: Arbitrary {
    public static var arbitrary: Gen<PsiCashBalance> {
        Gen.zip(BalanceIncreaseExpectationReason?.arbitrary,
                PsiCashAmount.arbitrary,
                PsiCashAmount.arbitrary)
            .map(PsiCashBalance.init(pendingExpectedBalanceIncrease:optimisticBalance:lastRefreshBalance:))
    }
}

extension IAPReducerState: Arbitrary {
    
    public static var arbitrary: Gen<IAPReducerState> {
        PsiCashAuthPackage.arbitrary.flatMap { (authPackage: PsiCashAuthPackage) in
            if authPackage.hasMinimalTokens {
                return Gen.zip(IAPState.arbitrary, PsiCashBalance.arbitrary,
                               Gen.pure(PsiCashAuthPackage.completeAuthPackage))
                    .map(IAPReducerState.init(iap:psiCashBalance:psiCashAuth:))
            } else {
                return Gen.zip(IAPState.arbitrary, Gen.pure(PsiCashBalance()),
                               Gen.pure(PsiCashAuthPackage(withTokenTypes: [])))
                    .map(IAPReducerState.init(iap:psiCashBalance:psiCashAuth:))
            }
        }
    }
    
    /// `arbitraryWithNonPurchasingState` satisfies the following condition:
    ///
    /// ```
    ///  (∀ type, state.iap.purchasing[type] == nil) &&
    ///  state.iap.unverifiedPsiCashTx == nil &&
    ///  state.psiCashAuth.hasMinimalTokens
    /// ```
    static let arbitraryWithNonPurchasingState = Gen<IAPReducerState>.compose { c in
        IAPReducerState(
            iap: IAPState(
                unverifiedPsiCashTx: nil,
                purchasing: [:]
            ),
            psiCashBalance: c.generate(),
            psiCashAuth: PsiCashAuthPackage.completeAuthPackage
        )
    }
    
    /// `arbitraryWithPurchasePending` satisfies the following condition:
    ///
    /// ```
    /// (∃ type, state.iap.purchasing[type]?.purchasingState == .pending(_))
    /// ```
    ///
    /// Returned IAPPurchasableProduct is the product in the last element of
    /// returned `IAPReducerState.iap.purchasing`
    static let arbitraryWithPurchasePending: Gen<Pair<IAPReducerState, AppStoreProduct>> =
        Gen.zip(
            IAPReducerState.arbitraryWithNonPurchasingState,
            AppStoreProduct.arbitrary,
            Payment?.arbitrary
        ).map {
            let purchasing = IAPPurchasing(productType: $1.type,
                                           productID: $1.productID,
                                           purchasingState: .pending($2))
            
            // Updates generated `IAPReducerState.iap.purchasing` value
            // with given `AppStoreProduct` as the pending purchase.
            var updatedState = $0
            updatedState.iap.purchasing[purchasing.productType] = purchasing
            
            return Pair(updatedState, $1)
    }
    
    /// `arbitraryWithPurchasePendingNoPayment` satisfies the following condition:
    ///
    /// ```
    /// (∃ type, state.iap.purchasing[type]?.purchasingState == .pending(nil))
    /// ```
    ///
    /// Returned IAPPurchasableProduct is the product in the last element of
    /// returned `IAPReducerState.iap.purchasing`
    static let arbitraryWithPurchasePendingNoPayment: Gen<Pair<IAPReducerState, AppStoreProduct>> =
        Gen.zip(
            IAPReducerState.arbitraryWithNonPurchasingState,
            AppStoreProduct.arbitrary
        ).map {
            let purchasing = IAPPurchasing(productType: $1.type,
                                           productID: $1.productID,
                                           purchasingState: .pending(nil))
            
            // Updates generated `IAPReducerState.iap.purchasing` value
            // with given `AppStoreProduct` as the pending purchase.
            var updatedState = $0
            updatedState.iap.purchasing[purchasing.productType] = purchasing
            
            return Pair(updatedState, $1)
    }
    
    
    /// `arbitraryWithPendingVerificationPurchaseState` satisfies the following condition:
    ///
    /// ```
    /// state.iap.unverifiedPsiCashTx != nil
    /// ```
    static let arbitraryWithPendingVerificationPurchaseState = Gen<IAPReducerState>.compose { c in
        IAPReducerState(
            iap: IAPState(
                unverifiedPsiCashTx: c.generate(using:UnfinishedConsumableTransaction.arbitrary),
                purchasing: c.generate()
            ),
            psiCashBalance: c.generate(),
            psiCashAuth: c.generate()
        )
    }
    
    /// `arbitraryWithMissingPsiCashTokens` satisfies the following condition:
    ///
    /// ```
    ///  state.iap.unverifiedPsiCashTx == nil &&
    ///     !(state.psiCashAuth.hasMinimalTokens)
    /// ```
    static let arbitraryWithMissingPsiCashTokens = Gen<IAPReducerState>.compose { c in
        IAPReducerState(
            iap: IAPState(
                unverifiedPsiCashTx: nil,
                purchasing: c.generate()
            ),
            psiCashBalance: c.generate(),
            psiCashAuth: PsiCashAuthPackage(withTokenTypes: [])
        )
    }
    
}

extension PsiCashValidationResponse.ResponseError: Arbitrary {
    public static var arbitrary: Gen<PsiCashValidationResponse.ResponseError> {
        Gen.one(of: [
            // Should cover all cases
            SystemError.arbitrary.map(PsiCashValidationResponse.ResponseError.failedRequest),
            
            HTTPResponseMetadata.arbitrary
                .map(PsiCashValidationResponse.ResponseError.errorStatusCode)
        ])
    }
}

extension PsiCashValidationResponse: Arbitrary {
    public static var arbitrary: Gen<PsiCashValidationResponse> {
        Gen.compose { c in
            PsiCashValidationResponse(result: c.generate())
        }
    }
}

extension PsiCashRefreshError: Arbitrary {
    public static var arbitrary: Gen<PsiCashRefreshError> {
        Gen.one(of: [
            // Should cover all cases
            Gen.pure(.tunnelNotConnected),
            Gen.pure(.serverError),
            Gen.pure(.invalidTokens),
            SystemError.arbitrary.map(PsiCashRefreshError.error)
        ])
    }
}

extension TransactionUpdate: Arbitrary {
    public static var arbitrary: Gen<TransactionUpdate> {
        Gen.frequency([
            // Should cover all cases
            (4, [PaymentTransaction].arbitrary
                .map(TransactionUpdate.updatedTransactions)),
            (1, Optional<SystemError>.arbitrary
                .map(TransactionUpdate.restoredCompletedTransactions(error:)))
        ])
    }
    
    /// Returns a generator that only generates `TransactionUpdate.restoredCompletedTransactions(error:)` case.
    static var arbitraryWithOnlyRestoredCompletedTransactionsCase: Gen<TransactionUpdate> {
        SystemError?.arbitrary.map(TransactionUpdate.restoredCompletedTransactions(error:))
    }
    
    /// Returns a generator that only generates `TransactionUpdate.updatedTransactions` case
    /// with possibly duplicate associated values.
    static var arbitraryWithOnlyUpdatedTransactionsCaseWithDuplicates: Gen<TransactionUpdate> {
        PaymentTransaction.arbitrary.proliferateWithDuplicates()
            .map(TransactionUpdate.updatedTransactions)
    }
    
}

extension ProductID: Arbitrary {
    /// Generates ProductID prefixed with one of the values from `AppStoreProductIdPrefixes`.
    public static var arbitrary: Gen<ProductID> {
        Gen.zip(
            Gen.fromElements(of: AppStoreProductIdPrefixes.allCases),
            String.arbitrary
        ).map { prefix, postfix -> ProductID in
            ProductID(rawValue: "\(prefix.rawValue).\(postfix)")!
        }
    }
}

extension SupportedAppStoreProducts: Arbitrary {
    public static var arbitrary: Gen<SupportedAppStoreProducts> {
        Set<ProductID>.arbitrary.map { productIdSet -> SupportedAppStoreProducts in
            let supportedSeq = productIdSet.map { productID -> (AppStoreProductType, ProductID) in
                let productType =
                    AppStoreProductIdPrefixes.estimateProductTypeFromPrefix(productID)!
                
                return (productType, productID)
            }
            
            return SupportedAppStoreProducts(supportedSeq)
        }
    }
}

extension SubscriptionIAPPurchase: Arbitrary {
    public static var arbitrary: Gen<SubscriptionIAPPurchase> {
        Gen.compose { c in
            return SubscriptionIAPPurchase(
                productID: c.generate(),
                transactionID: c.generate(),
                originalTransactionID: c.generate(),
                webOrderLineItemID: c.generate(),
                purchaseDate: c.generate(),
                expires: c.generate(),
                isInIntroOfferPeriod: c.generate(),
                hasBeenInIntroOfferPeriod: c.generate())
        }
    }
}

extension ConsumableIAPPurchase: Arbitrary {
    public static var arbitrary: Gen<ConsumableIAPPurchase> {
        Gen.compose { c in
            ConsumableIAPPurchase(productID: c.generate(), transactionID: c.generate())
        }
    }
}

extension ReceiptData: Arbitrary {
    public static var arbitrary: Gen<ReceiptData> {
        Gen.compose { c in
            ReceiptData(subscriptionInAppPurchases: c.generate(),
                        consumableInAppPurchases: c.generate(),
                        data: Data(), // TODO: currently unused in testing
                        readDate: c.generate())
        }
    }
}

extension ReceiptReadReason: Arbitrary {
    public static var arbitrary: Gen<ReceiptReadReason> {
        Gen<ReceiptReadReason>.fromElements(of: ReceiptReadReason.allCases)
    }
}

// Mirror of function of the same name in `SubscriptionIAPPurchase` for testing.
func isApproximatelyExpired(date: Date) -> Bool {
    switch compareDates(Date(), to: date) {
        case .orderedAscending: return false
        case .orderedDescending: return true
        case .orderedSame: return true
    }
}

func compareDates(_ date1: Date, to date2: Date) -> ComparisonResult {
    return Calendar.current.compare(date1,
                                    to: date2,
                                    toGranularity: .second)
}
