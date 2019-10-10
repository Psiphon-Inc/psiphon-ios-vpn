/*
 * Copyright (c) 2019, Psiphon Inc.
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
import SwiftActors
import RxSwift
import Promises

infix operator | : TernaryPrecedence


class IAPActor: Actor {

    struct Params {
        let actorBuilder: ActorBuilder
        let appBundle: Bundle
        let subscriptonActorParam: SubscriptionActor.Param
    }

    enum Action: AnyMessage {
        /// Adds `SKProduct` to the StoerKit's payment queue.
        case buyProduct(SKProduct)

        /// Sends a receipt refresh request to StoreKit.
        case refreshReceipt  // TODO! this shouldn't be exposed to the clientsl.

        /// Restores previously completed purchases.
        case restoreTransactions

        /// Removes pending PsiCash transactions from the payment queue.
        case completePsiCashTransactions
    }

    /// StoreKit request results
    fileprivate enum RequestResult: AnyMessage {
        case receiptRefreshResult(Result<Void, Error>)
    }

    /// StoreKit transaction obersver
    fileprivate enum TransactionMessage: AnyMessage {
        case updatedTransaction(Result<[SKPaymentTransaction], Error>)
        case didChangeStoreFront
        case restoredCompletedTransactions(error: Error?)
    }

    var context: ActorContext!
    let param: Params
    var subscriptionActor: ActorRef!
    var psiCashPendingTransactions = [SKPaymentTransaction]()
    private var paymentTransactionDelegate: PaymentTransactionDelegate!

    /// Notifies `subscriptionActor` of the updated receipt data (if any).
    var receiptData: ReceiptData? = .none {
        didSet {
            self.subscriptionActor ! SubscriptionActor.Action.updatedReceiptData(data)
        }
    }

    lazy var receive = behavior { [unowned self] in
        switch $0 {
        case let msg as Action:
            switch msg {
            case .buyProduct(let product): self.buyProduct(product)
            // TODO!!! this shouldn't be exposed to the user.
            case .refreshReceipt: self.refreshReceipt()
            case .restoreTransactions: self.restoreTransactions()
            case .completePsiCashTransactions: self.completePsiCashTransactions()
            }

        case let msg as TransactionMessage: self.handleStoreKitTransaction(msg)
        case let msg as RequestResult: self.handleRequestResult(msg)
        default: return .unhandled($0)
        }

        return .same
    }


    // MARK: -

    required init(_ param: Params) {
        self.param = param
    }

    func buyProduct(_ product: SKProduct) {
        SKPaymentQueue.default().add(SKPayment(product: product))
    }

    func refreshReceipt() {
        let responseDelegate = ReceiptRefreshRequestDelegate(replyTo: self)
        let request = SKReceiptRefreshRequest()
        request.delegate = responseDelegate
        request.start()
    }

    func restoreTransactions() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    func completePsiCashTransactions() {
        // Completes all pending PsiCash transactions.
        for tx in self.psiCashPendingTransactions {
            SKPaymentQueue.default().finishTransaction(tx)
        }
        self.psiCashPendingTransactions.removeAll()
    }

    private func handleRequestResult(_ msg: RequestResult) {
        switch msg {
        case .receiptRefreshResult(let result):
            switch result {
            case .success:
                self.receiptData = .fromLocalReceipt(self.param.appBundle)
            case .failure(_):
                // TODO!! maybe show an error message to the user
                break
            }

        }
    }

    private func handleStoreKitTransaction(_ msg: TransactionMessage) {
        switch msg {

        case .updatedTransaction(let result):
            switch result {

            case .success(let transactions):
                var updateReceiptData = false
                for transaction in transactions {

                    switch transaction.transactionState {
                    case .purchasing, .deferred:
                        break

                    case .failed:
                        break // TODO!!! report error to the user.

                    case .purchased:
                        switch try! ProductIdType.type(of: transaction) {
                        case .psiCash:
                            self.psiCashPendingTransactions.append(transaction)
                        case .subscription:
                            SKPaymentQueue.default().finishTransaction(transaction)
                        }
                        updateReceiptData = true

                    case .restored:
                        SKPaymentQueue.default().finishTransaction(transaction)
                        updateReceiptData = true

                    @unknown default:
                        assertionFailure("unknown transaction state \(transaction.transactionState)")
                    }
                }
                if updateReceiptData {
                    self.receiptData = .fromLocalReceipt(self.param.appBundle)
                }

            case .failure(let error):
                print(#file, #line, "failed updated transactions: \(error)")
            }

        case .didChangeStoreFront:
            print(#file, #line, "did change store front")

        case .restoredCompletedTransactions:
            print(#file, #line, "completed transactions finished")
            self.receiptData = .fromLocalReceipt(self.param.appBundle)

        }
    }

    func preStart() {
        // TODO!!! finish this
        /// According to https://developer.apple.com/documentation/storekit/in-app_purchase/setting_up_the_transaction_observer_and_payment_queue
        /// this should be added in AppDelegate didFinishLaunchingWithOptions.
        self.paymentTransactionDelegate = PaymentTransactionDelegate(replyTo: self)
        SKPaymentQueue.default().add(self.paymentTransactionDelegate)

        // Creates the subscription actor.
        let props = Props(SubscriptionActor.self,
                          param: self.param.subscriptonActorParam,
                          qos: .userInteractive)
        self.subscriptionActor = self.param.actorBuilder.makeActor(self, props, type: .subscription)
        self.receiptData = .fromLocalReceipt(self.param.appBundle)
    }

    func postStop() {
        SKPaymentQueue.default().remove(self.paymentTransactionDelegate)
    }

}

/// Sorts `products` in ascending order by price.
func sortedByPrice(_ products: [SKProduct]) -> [SKProduct] {
    return products.sorted {
        $0.price.compare($1.price) == .orderedAscending
    }
}


/// ActorDelegate for StoreKit transactions.
fileprivate class PaymentTransactionDelegate: ActorDelegate, SKPaymentTransactionObserver {

    // Sent when transactions are removed from the queue (via finishTransaction:).
    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions
        transactions: [SKPaymentTransaction]) {
        // NO-OP
    }

    // Sent when an error is encountered while adding transactions from the user's purchase history back to the queue.
    func paymentQueue(_ queue: SKPaymentQueue,
                      restoreCompletedTransactionsFailedWithError error: Error) {
        actor ! IAPActor.TransactionMessage.restoredCompletedTransactions(error: error)
    }

    // Sent when all transactions from the user's purchase history have successfully been added back to the queue.
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        actor ! IAPActor.TransactionMessage.restoredCompletedTransactions(error: .none)
    }

    // Sent when a user initiates an IAP buy from the App Store
    @available(iOS 11.0, *)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment,
                      for product: SKProduct) -> Bool {
        return false
    }

    // Sent when the transaction array has changed (additions or state changes).
    // Client should check state of transactions and finish as appropriate.
    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        actor ! IAPActor.TransactionMessage.updatedTransaction(.success(transactions))
    }

    @available(iOS 13.0, *)
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        // TODO! check what this does and how we need to react
        actor ! IAPActor.TransactionMessage.didChangeStoreFront
    }

}


/// ActorDelegate for StoreKit receipt refresh request: `SKReceiptRefreshRequest`.
fileprivate class ReceiptRefreshRequestDelegate: ActorDelegate, SKRequestDelegate {

    func requestDidFinish(_ request: SKRequest) {
        actor ! IAPActor.RequestResult.receiptRefreshResult(.success(()))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        actor ! IAPActor.RequestResult.receiptRefreshResult(.failure(error))
    }

}
