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

enum IAPPurchasingState: Equatable {
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
    
    var paymentStatus: Pending<Result<Unit, ErrorEvent<IAPError>>> {
        didSet {
            guard case .subscription(product: _, promise: let promise) = product else {
                return
            }
            guard case .completed(let completedResult) = paymentStatus else {
                return
            }
            promise.fulfill(IAPResult(transaction: nil, result: completedResult))
        }
    }
    
    init(product: IAPPurchasableProduct,
         paymentStatus: Pending<Result<Unit, ErrorEvent<IAPError>>>) {
        self.product = product
        self.paymentStatus = paymentStatus
        self.paymentObj = nil
    }
    
}

enum UnverifiedPsiCashTransactionState: Equatable {
    case pendingVerification(UnverifiedPsiCashConsumableTransaction)
    case pendingVerificationResult(UnverifiedPsiCashConsumableTransaction)
    
    var transaction: UnverifiedPsiCashConsumableTransaction {
        switch self {
        case .pendingVerification(let value): return value
        case .pendingVerificationResult(let value): return value
        }
    }
}

struct IAPState: Equatable {
    
    /// PsiCash consumable transaction pending server verification.
    var unverifiedPsiCashTx: UnverifiedPsiCashTransactionState?
    
    var purchasing: IAPPurchasingState {
        willSet {
            guard case let .pending(.subscription(product: _, promise: promise)) = purchasing else {
                return
            }
            switch newValue {
            case .none:
                promise.fulfill(IAPResult(transaction: nil, result: .success(.unit)))
            case .error(let errorEvent):
                promise.fulfill(IAPResult(transaction: nil, result: .failure(errorEvent)))
            case .pending(_):
                return
            }
        }
    }
    
    init() {
        self.purchasing = .none
        self.unverifiedPsiCashTx = nil
    }
}

/// Represents payment object for product types through AppStore.
enum IAPPaymentType: Hashable {
    case psiCash(SKPayment)
    
    /// Result type error is from SKPaymentTransaction error:
    /// https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411269-error
    case subscription(SKPayment, Promise<IAPResult>)
}

struct IAPResult {
    let transaction: SKPaymentTransaction?
    let result: Result<Unit, ErrorEvent<IAPError>>
}

enum IAPPurchasableProduct: Hashable {
    case psiCash(product: AppStoreProduct)
    
    /// Since subscription implementation is in Objective-C, communication of purchase result
    /// is done using a promise object.
    case subscription(product: AppStoreProduct, promise: Promise<IAPResult>)
}

enum IAPError: HashableError {
    case failedToCreatePurchase(reason: String)
    case storeKitError(Either<SKError, SystemError>)
}

extension IAPError {
    /// True if payment is cancelled by the user
    var paymentCancelled: Bool {
        guard case let .storeKitError(.left(skError)) = self else {
            return false
        }
        guard case .paymentCancelled = skError.code else {
            return false
        }
        return true
    }
}
