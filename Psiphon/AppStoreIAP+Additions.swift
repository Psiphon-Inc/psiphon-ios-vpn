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
import AppStoreIAP
import PsiApi

extension PaymentQueue {
    
    static let `default` = PaymentQueue(
        transactions: {
            Effect {
                SKPaymentQueue.default().transactions.map(PaymentTransaction.make(from:))
            }
        },
        addPayment: { purchasable in
            Effect { () -> AddedPayment in
                let payment = SKPayment(product: purchasable.appStoreProduct.skProductRef!)
                SKPaymentQueue.default().add(payment)
                return AddedPayment(purchasable, payment)
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
                guard let skPaymentTransaction = transaction.skPaymentTransaction() else {
                    return
                }
                SKPaymentQueue.default().finishTransaction(skPaymentTransaction)
            }
        })
    
}

extension PaymentTransaction.TransactionState: FeedbackDescription {}

extension PaymentTransaction: CustomFieldFeedbackDescription {
    
    public var feedbackFields: [String: CustomStringConvertible] {
        ["transactionID": self.transactionID(),
         "productID": self.productID(),
         "transactionState": makeFeedbackEntry(self.transactionState())]
    }
    
}

extension ReceiptData: FeedbackDescription {}
