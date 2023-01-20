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

/// Represents a transaction with transaction state `SKPaymentTransactionState.purchased`
/// that has not been finished, pending verification by the purchase-verifier server.
public struct UnifinishedTransaction: Equatable {
    
    /// Represents verification status of an IAP through App Store.
    public enum VerificationStatus: Equatable {
        
        /// No verification request for this purchase has been made.
        case notRequested
        
        /// Request is submitted, and is pending response from the verifier server.
        case pendingResponse
        
        /// Request to verify purchase failed.
        case requestError(ErrorEvent<ErrorRepr>)
        
    }
    
    public let transaction: AppStorePaymentTransaction
    
    public let verificationStatus: VerificationStatus
    
    public init(
        transaction: AppStorePaymentTransaction,
        verificationStatus: VerificationStatus
    ) {
        self.transaction = transaction
        self.verificationStatus = verificationStatus
    }
    
}

public struct IAPState: Equatable {
   
    /// Similar to`PaymentTransaction.TransactionState` with different error states.
    public typealias AppStorePurchaseState =
    PendingValue<
        AppStorePaymentTransaction.TransactionState.PendingTransactionState,
        Result<UnifinishedTransaction, ErrorEvent<IAPError>>
    >
    
    /// Represents possible failed states when making an in-app purchase.
    public enum IAPError: HashableError {
        
        /// Represents an error state where the in-app purchase purchase could not be created,
        /// usually due to missing data (e.g. PsiCash tokens).
        case failedToCreatePurchase(reason: String)
        
        /// Represents a StoreKit error.
        case storeKitError(AppStorePaymentTransaction.TransactionState.TransactionErrorState)
        
    }
    
    /// Contains products being purchased through App Store.
    /// - Note: that this dictionary only contains state of the last transaction for each `AppStoreProductType`.
    public var purchasing: [AppStoreProductType: AppStorePurchaseState]
    
    public var objcSubscriptionPromises = [Promise<ObjCIAPResult>]()
    
    public init() {
        self.purchasing = [:]
    }
    
    init(
        purchasing: [AppStoreProductType: AppStorePurchaseState]
    ) {
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

extension IAPState.AppStorePurchaseState: FeedbackDescription {}
