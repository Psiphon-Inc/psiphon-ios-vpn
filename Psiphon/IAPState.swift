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

struct PendingPayment: Hashable {
    // For example what should happen in the case of PsiCash
    let payment: PaymentType
    var paidSuccessfully: Pending<Result<Unit, ErrorEvent<IAPError>>>
}

struct IAPState: Equatable {
    var payments: Set<PendingPayment> // TODO! Something needs to clear these payments
    
    /// PsiCash consumable transaction pending server verification.
    var unverifiedPsiCashTransaction: UnverifiedPsiCashConsumableTransaction?
}

extension IAPState {
    init() {
        payments = Set()
        unverifiedPsiCashTransaction = nil
    }
}

enum PaymentType: Hashable {
    case psiCash(SKPayment)
    
    /// Result type error is from SKPaymentTransaction error:
    /// https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411269-error
    case subscription(SKPayment, Promise<IAPResult>)
}

struct IAPResult {
    /// Updated payment transaction.
    /// -Note SKPaymenTransaction is wrapped along with the result
    /// for easier ObjC compatibility.
    let transaction: SKPaymentTransaction?
    let result: Result<(), ErrorEvent<IAPError>>
}

// TODO! rename
enum PurchasableProduct {
    case psiCash(product: AppStoreProduct)
    
    /// Since subscription implementation is in Objective-C, communication of purchase result
    /// is done using a promise object.
    case subscription(product: AppStoreProduct, promise: Promise<IAPResult>)
}

// TODO! This is not needed. Since these results aren't returned together
enum IAPError: HashableError {
    case waitingForPendingTransactions
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
