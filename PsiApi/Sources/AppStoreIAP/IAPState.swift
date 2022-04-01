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

public struct IAPPurchasing: Hashable, FeedbackDescription {
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
    ///
    /// - Parameter existingConsumableTransaction: Called for consumable transactions.
    ///  It should return `.none` if the passed in `PaymentTransaction` is a new unique transaction,
    ///  `.some(true)` if a consumable transaction has already been observed with the same payment transaction id,
    ///  and `.some(false)` if a consumable transaction has already been observed but with a different payment transaction id
    ///  or the transaction state is not  "purchased" (i.e. `SKPaymentTransactionStatePurchased`) yet
    ///
    /// - Note: that payment transaction id is not the same as transaction id present in the receipt file.
    /// - Returns: `nil` if the transaction has completed successfully, and hence no longer in a purchasing state.
    public static func make(
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

/// Represents  a consumable transaction with transaction state `SKPaymentTransactionState.purchased`
/// that has not been finished, pending verification by the purchase-verifier server.
public struct UnfinishedConsumableTransaction: Equatable, FeedbackDescription {
    
    public enum VerificationRequestState: Equatable {
        
        /// No verification request for this purchase has been made.
        case notRequested
        
        /// Request is submitted, and is pending response from the verifier server.
        case pendingResponse
        
        /// Request to verify purchase failed.
        case requestError(ErrorEvent<ErrorRepr>)
        
    }
    
    public var completedTransaction: PaymentTransaction.CompletedTransaction {
        guard
            case .completed(.success(let completedTx)) = self.transaction.transactionState()
        else {
            fatalError()
        }
        return completedTx
    }
    
    // Wraps the SKPaymentTransaction object.
    public let transaction: PaymentTransaction
    
    // Represents verification state of this transaction against the purchase-verifier server.
    public var verificationState: VerificationRequestState
    
    public init?(
        completedTransaction: PaymentTransaction,
        verificationState: VerificationRequestState
    ) {
        
        // Only transactions with SKPaymentTransactionState of
        // SKPaymentTransactionStatePurchased or SKPaymentTransactionStateRestored
        // can be verified. i.e. the payment for the purchase has been completed by the user.
        guard
            case .completed(.success(_)) = completedTransaction.transactionState()
        else {
            return nil
        }
        
        self.transaction = completedTransaction
        self.verificationState = verificationState
    }
}

public struct IAPState: Equatable {
    
    /// PsiCash consumable transaction pending server verification.
    /// We only ever expect a single unfinished consumable transaction as per Apple documentation.
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
