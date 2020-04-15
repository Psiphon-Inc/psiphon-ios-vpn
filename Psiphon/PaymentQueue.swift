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
import StoreKit
import ReactiveSwift

struct PaymentQueue {
    let transactions: () -> Effect<[SKPaymentTransaction]>
    let addPayment: (IAPPurchasableProduct) -> Effect<AddedPayment>
    let addObserver: (SKPaymentTransactionObserver) -> Effect<Never>
    let removeObserver: (SKPaymentTransactionObserver) -> Effect<Never>
    let finishTransaction: (SKPaymentTransaction) -> Effect<Never>
}

/// Represents a payment that has been added to `SKPaymentQueue`.
struct AddedPayment {
    let product: IAPPurchasableProduct
    let paymentObj: SKPayment
}

typealias PurchaseAddedResult = Result<AddedPayment, ErrorEvent<IAPError>>

extension PaymentQueue {
    
    static let `default` = PaymentQueue(
        transactions: {
            Effect {
                SKPaymentQueue.default().transactions
            }
        },
        addPayment: { purchasable in
            Effect { () -> AddedPayment in
                let payment = SKPayment(product: purchasable.appStoreProduct.skProduct)
                SKPaymentQueue.default().add(payment)
                return AddedPayment(product: purchasable, paymentObj: payment)
            }
        },
        addObserver: { observer in
            .fireAndForget {
                SKPaymentQueue.default().add(observer)
            }
        },
        removeObserver: { observer in
            .fireAndForget {
                SKPaymentQueue.default().remove(observer)
            }
        },
        finishTransaction: { transaction in
            .fireAndForget {
                SKPaymentQueue.default().finishTransaction(transaction)
            }
        })
    
    func addPurchase(_ purchasable: IAPPurchasableProduct) -> Effect<PurchaseAddedResult> {
        transactions().flatMap(.latest) { transactions -> Effect<PurchaseAddedResult> in
            self.addPayment(purchasable).map {
                .success($0)
            }
        }
    }

}
