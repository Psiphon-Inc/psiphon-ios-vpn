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
import PsiApi

public struct PaymentQueue {
    public let transactions: () -> Effect<[PaymentTransaction]>
    public let addPayment: (IAPPurchasableProduct) -> Effect<AddedPayment>
    public let addObserver: (SKPaymentTransactionObserver) -> Effect<Never>
    public let removeObserver: (SKPaymentTransactionObserver) -> Effect<Never>
    public let finishTransaction: (PaymentTransaction) -> Effect<Never>
    
    public init(transactions: @escaping () -> Effect<[PaymentTransaction]>,
                addPayment: @escaping (IAPPurchasableProduct) -> Effect<AddedPayment>,
                addObserver: @escaping (SKPaymentTransactionObserver) -> Effect<Never>,
                removeObserver: @escaping (SKPaymentTransactionObserver) -> Effect<Never>,
                finishTransaction: @escaping (PaymentTransaction) -> Effect<Never>) {
        self.transactions = transactions
        self.addPayment = addPayment
        self.addObserver = addObserver
        self.removeObserver = removeObserver
        self.finishTransaction = finishTransaction
    }
    
}

/// Represents a payment that has been added to `SKPaymentQueue`.
public struct AddedPayment: Equatable {
    public let product: IAPPurchasableProduct
    public let paymentObj: SKPayment
    
    public init(_ product: IAPPurchasableProduct, _ paymentObj: SKPayment) {
        self.product = product
        self.paymentObj = paymentObj
    }
    
}
