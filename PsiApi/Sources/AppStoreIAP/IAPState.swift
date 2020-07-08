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

/// Represents possible failed states when making an in-app purchase.
public enum IAPError: HashableError {
    
    /// Represents an error state where the in-app purchase purchase could not be created,
    /// usually due to missing data (e.g. PsiCash tokens).
    case failedToCreatePurchase(reason: String)
    
    /// Represents a StoreKit error.
    case storeKitError(PaymentTransaction.TransactionState.TransactionErrorState)
}

public struct IAPPurchasing: Hashable {
    public typealias PurchasingState = PendingValue<Payment?, ErrorEvent<IAPError>>
    
    public enum TransactionUniqueness: Equatable {
        case unique(IAPPurchasing?, UnfinishedConsumableTransaction?)
        case duplicate
        
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
                        completedTransaction: tx,
                        verificationState: .notRequested
                    )
                    
                    return .success(.unique(nil, unfinishedTx))

                case .some(_):
                    // Transaction is a duplicate.
                    return .success(.duplicate)
                }
            }
        }
    }
    
}

/// Represents  a consumable transaction has not been finished, pending verification by the purchase-verifier server.
public struct UnfinishedConsumableTransaction: Equatable {
    
    public enum VerificationRequestState: Equatable {
        /// No verification request for this purchase has been made.
        case notRequested
        
        /// Request is submitted, and is pending response from the verifier server.
        case pendingResponse
        
        /// Request to verify purchase failed.
        case requestError(ErrorEvent<ErrorRepr>)
        
        /// Purchase has been made, however App Store has not recorded the
        ///
        /// To resolve the error user can be prompted to refresh the App Store receipt,
        /// however this may not always resolve the issue if for example device is jailbroken.
        case purchaseNotRecordedByAppStore
    }
    
    public let transaction: PaymentTransaction
    public let completedTransaction: PaymentTransaction.CompletedTransaction
    public var verification: VerificationRequestState
    
    public init?(completedTransaction: PaymentTransaction,
                 verificationState: VerificationRequestState) {
        // An uncompleted transaction is not verifiable.
        guard
            case .completed(.success(let completedTx)) = completedTransaction.transactionState()
        else {
            return nil
        }
        
        self.transaction = completedTransaction
        self.completedTransaction = completedTx
        self.verification = verificationState
    }
}

public struct IAPState: Equatable {
    
    /// PsiCash consumable transaction pending server verification.
    public var unfinishedPsiCashTx: UnfinishedConsumableTransaction?
    
    /// Contains products currently being purchased.
    public var purchasing: [AppStoreProductType: IAPPurchasing]
    
    public var objcSubscriptionPromises = [Promise<ObjCIAPResult>]()
    
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
