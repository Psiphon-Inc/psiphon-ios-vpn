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

public enum IAPPurchasingState: Equatable {
    case none
    case error(ErrorEvent<IAPError>)
    case pending(IAPPurchasableProduct)
    
    /// True if purchasing is completed (succeeded or failed)
    var completed: Bool {
        switch self {
        case .none: return true
        case .error(_): return true
        case .pending(_): return false
        }
    }
}

struct PendingPayment: Hashable {
    // For example what should happen in the case of PsiCash
    let product: IAPPurchasableProduct
    var paymentObj: SKPayment?
    
    var paymentStatus: Pending<Result<Utilities.Unit, ErrorEvent<IAPError>>> {
        didSet {
            guard case .subscription(product: _, promise: let promise) = product else {
                return
            }
            guard case .completed(let completedResult) = paymentStatus else {
                return
            }
            promise?.fulfill(IAPResult(transaction: nil, result: completedResult))
        }
    }
    
    init(product: IAPPurchasableProduct,
         paymentStatus: Pending<Result<Utilities.Unit, ErrorEvent<IAPError>>>) {
        self.product = product
        self.paymentStatus = paymentStatus
        self.paymentObj = nil
    }
    
}

public struct UnverifiedPsiCashTransactionState: Equatable {
    
    public enum VerificationRequestState: Equatable {
        case notRequested
        case pendingVerificationResult
        case requestError(ErrorEvent<ErrorRepr>)
    }
    
    public let transaction: PaymentTransaction
    public let verificationState: VerificationRequestState
    
    public init?(transaction: PaymentTransaction, verificationState: VerificationRequestState) {
        // An uncompleted transaction is not verifiable.
        guard case .completed(.success(_)) = transaction.transactionState() else {
            return nil
        }
        self.transaction = transaction
        self.verificationState = verificationState
    }
}

public struct IAPState: Equatable {
    
    /// PsiCash consumable transaction pending server verification.
    public var unverifiedPsiCashTx: UnverifiedPsiCashTransactionState?
    
    public var purchasing: IAPPurchasingState {
        willSet {
            guard case let .pending(.subscription(product: _, promise: promise)) = purchasing else {
                return
            }
            switch newValue {
            case .none:
                promise?.fulfill(IAPResult(transaction: nil, result: .success(.unit)))
            case .error(let errorEvent):
                promise?.fulfill(IAPResult(transaction: nil, result: .failure(errorEvent)))
            case .pending(_):
                return
            }
        }
    }
    
    public init() {
        self.purchasing = .none
        self.unverifiedPsiCashTx = nil
    }
    
    init(unverifiedPsiCashTx: UnverifiedPsiCashTransactionState?, purchasing: IAPPurchasingState) {
        self.unverifiedPsiCashTx = unverifiedPsiCashTx
        self.purchasing = purchasing
    }
}

/// Represents payment object for product types through AppStore.
public enum IAPPaymentType: Hashable {
    case psiCash(SKPayment)
    
    /// Result type error is from SKPaymentTransaction error:
    /// https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411269-error
    case subscription(SKPayment, Promise<IAPResult>)
}

extension IAPPaymentType {

    var paymentObject: SKPayment {
        switch self {
        case .psiCash(let value):
            return value
        case .subscription(let value, _):
            return value
        }
    }

}

public struct IAPResult {
    public let transaction: SKPaymentTransaction?
    public let result: Result<Utilities.Unit, ErrorEvent<IAPError>>
}

public enum IAPPurchasableProduct: Hashable {
    case psiCash(product: AppStoreProduct)
    
    /// Since subscription implementation is in Objective-C, communication of purchase result
    /// is done using a promise object.
    case subscription(product: AppStoreProduct, promise: Promise<IAPResult>?)
}

extension IAPPurchasableProduct {
    
    public var appStoreProduct: AppStoreProduct {
        switch self {
        case let .psiCash(product: product): return product
        case let .subscription(product: product, promise: _): return product
        }
    }
    
}

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
