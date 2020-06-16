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
import Promises
import Utilities
import StoreKit
import PsiApi

public enum IAPError: HashableError {
    // Fully specified StoreKit error type.
    // Not all errors emitted by StoreKit are of type `SKError`.
    public typealias StoreKitError = Either<SystemError, SKError>
    
    case failedToCreatePurchase(reason: String)
    case storeKitError(StoreKitError)
}

extension IAPError.StoreKitError {
    /// True if payment is cancelled by the user
    public var paymentCancelled: Bool {
        guard case let .right(skError) = self else {
            return false
        }
        guard case .paymentCancelled = skError.code else {
            return false
        }
        return true
    }
}

public struct IAPPurchasing: Hashable {
    public typealias PurchasingState = PendingValue<Payment?, ErrorEvent<IAPError>>
    
    public enum TransactionUniqueness: Equatable {
        case unique(IAPPurchasing?, UnfinishedConsumableTransaction?)
        case nonUnique
        
        var iapPurchasing: IAPPurchasing? {
            guard case let .unique(a, _) = self else { return nil }
            return a
        }
    }
    
    public let productType: AppStoreProductType
    public let productID: ProductID
    public let purchasingState: PurchasingState
        
    /// True if purchase has completed, false if pending.
    var completed: Bool {
        switch purchasingState {
        case .pending: return false
        case .completed(_): return true
        }
    }
    
    init(
        productType: AppStoreProductType,
        productID: ProductID,
        purchasingState: PurchasingState
    ) {
        self.productType = productType
        self.productID = productID
        self.purchasingState = purchasingState
    }
 
    /// Creates `IAPPurchasing` value given updated transaction.
    /// Returns `nil` if the transaction has completed successfully, and hence no longer in a purchasing state.
    public static func makeGiven(
        productType: AppStoreProductType,
        transaction tx: PaymentTransaction,
        existingConsumableTransaction: (PaymentTransaction) -> Bool?,
        getCurrentTime: () -> Date
        ) -> Result<TransactionUniqueness, FatalError> {
        switch tx.transactionState() {
        case .pending(_):
            let iapPurchasing = IAPPurchasing(productType: productType,
                                              productID: tx.productID(),
                                              purchasingState: .pending(tx.payment()))
            return .success(.unique(iapPurchasing, nil))
            
        case let .completed(.failure(error)):
            let iapPurchasing = IAPPurchasing(productType: productType,
                                              productID: tx.productID(),
                                              purchasingState: .completed(ErrorEvent(
                                                .storeKitError(error),
                                                date: getCurrentTime())))
            
            return .success(.unique(iapPurchasing, nil))
            
        case .completed(.success(_)):
            switch productType {
            case .subscription:
                return .success(.unique(nil, nil))
                
            case .psiCash:
                switch existingConsumableTransaction(tx) {
                case .none:
                    let unfinishedTx = UnfinishedConsumableTransaction(
                        transaction: tx,
                        verificationState: .notRequested
                    )
                    
                    return .success(.unique(nil, unfinishedTx))

                case .some(false):
                    // Unexpected duplicate transaction.
                    return .success(.nonUnique)
                    
                case .some(true):
                    return .failure(FatalError("""
                        found two completed but unverified consumable purchases: \
                        new transaction id: '\(tx.transactionID())'
                        """))
                }
            }
        }
    }
    
}

/// Represents  a consumable transaction has not been finished pending verification by the purchase-verifier server.
public struct UnfinishedConsumableTransaction: Equatable {
    
    public enum VerificationRequestState: Equatable {
        case notRequested
        /// Request is submitted, and is pending response from the verifier server.
        case pendingResponse
        case requestError(ErrorEvent<ErrorRepr>)
    }
    
    public let transaction: PaymentTransaction
    public let verification: VerificationRequestState
    
    public init?(transaction: PaymentTransaction, verificationState: VerificationRequestState) {
        // An uncompleted transaction is not verifiable.
        guard case .completed(.success(_)) = transaction.transactionState() else {
            return nil
        }
        self.transaction = transaction
        self.verification = verificationState
    }
}

public struct IAPState: Equatable {
    
    /// PsiCash consumable transaction pending server verification.
    public var unfinishedPsiCashTx: UnfinishedConsumableTransaction?
    
    /// Contains products currently being purchased.
    public var purchasing: [AppStoreProductType: IAPPurchasing]
    
    public var objcSubscriptionPromise: Promise<ObjCIAPResult>? = nil
    
    public init() {
        self.purchasing = [:]
        self.unfinishedPsiCashTx = nil
    }
    
    init(
        unverifiedPsiCashTx: UnfinishedConsumableTransaction?,
        purchasing: [AppStoreProductType: IAPPurchasing]
    ) {
        self.unfinishedPsiCashTx = unverifiedPsiCashTx
        self.purchasing = purchasing
    }
}

// IAP result
@objc public final class ObjCIAPResult: NSObject {
    @objc public let transaction: SKPaymentTransaction?
    @objc public let error: Error?

    public init(transaction: SKPaymentTransaction?, error: Error?) {
        self.transaction = transaction
        self.error = error
    }
}
