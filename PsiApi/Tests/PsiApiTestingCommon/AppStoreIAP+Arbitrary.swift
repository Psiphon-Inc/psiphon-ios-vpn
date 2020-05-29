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
        Gen.zip(String.arbitrary, SignedAuthorization.arbitrary)
            .map(SignedData.init(rawData:decoded:))
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
            
            Result<Pair<Date, CompletedTransactionState>, SKError>.arbitrary
                .map(PaymentTransaction.TransactionState.completed)
        ])
    }
}

extension TransactionID: Arbitrary {
    public static var arbitrary: Gen<TransactionID> {
        Int.arbitrary.resize(999_999_999).map(
            comp(TransactionID.init(stringLiteral:), String.init, abs)
        )
    }
}

extension OriginalTransactionID: Arbitrary {
    public static var arbitrary: Gen<OriginalTransactionID> {
        Int.arbitrary.resize(999_999_999).map(
            comp(OriginalTransactionID.init(stringLiteral:), String.init, abs)
        )
    }
}

extension PaymentTransaction: Arbitrary {
    public static var arbitrary: Gen<PaymentTransaction> {
        Gen.zip(TransactionID.arbitrary, Date.arbitrary, String.arbitrary,
                TransactionState.arbitrary)
            .map({ (transactionID, date, productID, transactionState) in
                PaymentTransaction(
                    transactionID: { transactionID },
                    productID: { productID },
                    transactionState: { transactionState },
                    isEqual: { $0.transactionID() == transactionID },
                    skPaymentTransaction: { nil }
                )
            })
    }
}

extension UnverifiedPsiCashTransactionState.VerificationRequestState: Arbitrary {
    public static var arbitrary: Gen<UnverifiedPsiCashTransactionState.VerificationRequestState> {
        Gen.one(of: [
            // Should cover all cases
            Gen.pure(.notRequested),
            Gen.pure(.pendingVerificationResult),
            ErrorEvent<ErrorRepr>.arbitrary
                .map(UnverifiedPsiCashTransactionState.VerificationRequestState.requestError),
        ])
    }
}

extension UnverifiedPsiCashTransactionState: Arbitrary {
    public static var arbitrary: Gen<UnverifiedPsiCashTransactionState> {
        Gen.zip(PaymentTransaction.arbitrary, VerificationRequestState.arbitrary)
            .suchThat({ (paymentTransaction, _) -> Bool in
                if case .completed(.success(_)) = paymentTransaction.transactionState() {
                    return true
                }
                return false
            }).map {
                guard let value =
                    UnverifiedPsiCashTransactionState(transaction: $0, verificationState: $1) else {
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
        Gen.zip(AppStoreProductType.arbitrary, String.arbitrary,
                String.arbitrary, LocalizedPrice.arbitrary, Gen.pure(nil))
            .map(AppStoreProduct.init)
    }
}

extension IAPPurchasableProduct: Arbitrary {
    public static var arbitrary: Gen<IAPPurchasableProduct> {
        Gen.one(of: [
            // Should cover all cases
            AppStoreProduct.arbitrary.map(IAPPurchasableProduct.psiCash(product:)),
            
            Gen.zip(AppStoreProduct.arbitrary, Gen.pure(nil))
                .map(IAPPurchasableProduct.subscription(product: promise:))
        ])
    }
}

extension IAPError: Arbitrary {
    public static var arbitrary: Gen<IAPError> {
        Gen.one(of: [
            // Should cover all cases
            String.arbitrary.map(IAPError.failedToCreatePurchase(reason:)),
            SKError.arbitrary.map(IAPError.storeKitError)
        ])
    }
}

extension IAPPurchasingState: Arbitrary {
    public static var arbitrary: Gen<IAPPurchasingState> {
        Gen.frequency([
            // Should cover all cases
            (1, Gen.pure(.none)),
            (3, ErrorEvent<IAPError>.arbitrary.map(IAPPurchasingState.error)),
            (6, IAPPurchasableProduct.arbitrary.map(IAPPurchasingState.pending)),
        ])
    }
}

extension IAPState: Arbitrary {
    public static var arbitrary: Gen<IAPState> {
        Gen.zip(UnverifiedPsiCashTransactionState?.arbitrary, IAPPurchasingState.arbitrary)
            .map(IAPState.init(unverifiedPsiCashTx: purchasing:))
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
}

extension AddedPayment: Arbitrary {
    public static var arbitrary: Gen<AddedPayment> {
        Gen.zip(IAPPurchasableProduct.arbitrary, Gen.pure(SKPayment()))
            .map(AddedPayment.init(_: _:))
    }
}
