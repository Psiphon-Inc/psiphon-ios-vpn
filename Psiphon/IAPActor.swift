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
import ReactiveSwift
import Promises

enum PurchasableProduct {
    /// Althought customData is not used in the transaction with AppStore, it must be present
    /// to ensure that the user has valid PsiCash tokens to make an App Store purchase.
    case psiCash(product: AppStoreProduct, customData: CustomData)
    case subscription(product: AppStoreProduct)
}

/// Wraps a StoreKit PsiCash coin consumable transaction that has been verified and finished.
struct PsiCashConsumableTransaction: AnyMessage, Equatable {
    /// A verified and completed transaction.
    let transaction: SKPaymentTransaction
}

/// Wraps a `SKPayment` object with the associated promise sent to the actor with the product request.
fileprivate struct PendingPurchase: Hashable {
    let payment: SKPayment

    /// Result type error is from SKPaymentTransaction error:
    /// https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411269-error
    let promise: Promise<IAPResult>
}

struct IAPResult {
    /// Updated payment transaction.
    /// -Note SKPaymenTransaction is wrapped along with the result
    /// for easier ObjC compatibility.
    let transaction: SKPaymentTransaction?
    let result: Result<(), ErrorEvent<IAPError>>
}

enum IAPError: HashableError {
    case waitingForPendingTransactions
    case storeKitError(Either<SKError, SystemError>)
}

class IAPActor: Actor, OutputProtocol, TypedInput {
    typealias OutputType = OutputState
    typealias OutputErrorType = Never
    typealias InputType = Action

    struct Params {
        let pipeOut: OutputSignal.Observer
        let consumableTxObserver: TypedActor<PsiCashConsumableTransaction>
    }

    enum Action: Message {
        /// Adds `SKProduct` to the StoerKit's payment queue.
        case buyProduct(PurchasableProduct, Promise<IAPResult>)

        case refreshReceipt(Promise<Result<(), SystemErrorEvent>>)

        // Actor private messages
        case verifiedConsumableTransaction(PsiCashConsumableTransaction)
    }

    /// StoreKit request results
    enum RequestResult: AnyMessage {
        case receiptRefreshResult(Result<(), SystemErrorEvent>)
    }

    /// StoreKit transaction obersver
    fileprivate enum TransactionUpdate: AnyMessage {
        case updatedTransactions([SKPaymentTransaction])
        case didChangeStoreFront
        case restoredCompletedTransactions(error: Error?)
    }

    struct OutputState: Equatable {
        var subscription: SubscriptionState
        var iapState: State
    }

    struct State: Equatable {
        var pendingPsiCashPurchase: SKPaymentTransaction?
    }

    var context: ActorContext!
    private let (lifetime, token) = Lifetime.make()
    private let param: Params

    @ActorState private var state: State
    private var subscriptionActor = ObservableActor<SubscriptionActor, SubscriptionActor.Action>()
    private let paymenQueue = SKPaymentQueue.default()

    /// Set of promises, pending purchase result.
    private var pendingPurchasePromises = Set<PendingPurchase>()

    private lazy var paymentTransactionDelegate = PaymentTransactionDelegate(replyTo: self)
    private lazy var receiptRefreshDelegate = ReceiptRefreshRequestDelegate(replyTo: self)

    /// Notifies `subscriptionActor` of the updated receipt data (if any).
    private var receiptData: AppStoreReceipt? = .none {
        didSet {
            self.subscriptionActor.actor! ! .updatedReceiptData(receiptData)
        }
    }

    // TODO: review for ref cycle
    private lazy var refreshReceiptHandler =
        promiseAcc(effect: { [unowned self] in self.refreshReceipt() },
                           \Action.refreshReceipt,
                           \RequestResult.receiptRefreshResult)

    private lazy var defaultHandler: ActionHandler = { [unowned self] in
        switch $0 {
        case let msg as Action:
            switch msg {
            case let .buyProduct(product, promise):
                self.buyProduct(product, promise)
                return .same

            case .refreshReceipt(_):
                // Handled by `refreshReceiptHandler`.
                return .unhandled

            case .verifiedConsumableTransaction(let psiCashConsumable):
                guard let pendingConsumable = self.state.pendingPsiCashPurchase,
                    psiCashConsumable.transaction.isEqual(pendingConsumable) else {
                    fatalError("""
                        Verified an unknown consumable transaction \
                        '\(String(describing: psiCashConsumable))'
                        """)
                }

                self.paymenQueue.finishTransaction(pendingConsumable)
                self.state.pendingPsiCashPurchase = nil
                return .same
            }

        case let msg as TransactionUpdate:
            self.handleStoreKitTransaction(msg)
            return .same

        default:
            return .unhandled
        }
    }

    lazy var receive = self.defaultHandler <> self.refreshReceiptHandler

    private func buyProduct(_ purchasable: PurchasableProduct, _ promise: Promise<IAPResult>) {
        // Rejects product purchase if a transaction is already in progress.
        // Note that there is no callback from StoreKit if purchasing a product that is already
        // purchased.
        guard self.paymenQueue.transactions.count == 0 else {
            promise.fulfill(
                IAPResult(transaction: nil,
                          result: .failure(ErrorEvent(.waitingForPendingTransactions))))
            return
        }
        let payment = SKPayment(product: purchasable.appStoreProduct.skProduct)
        self.pendingPurchasePromises.insert(
            PendingPurchase(payment: payment, promise: promise))
        self.paymenQueue.add(payment)
    }

    private func refreshReceipt() {
        // TODO: Do we need to hold a reference to the request object?
        let request = SKReceiptRefreshRequest()
        request.delegate = self.receiptRefreshDelegate
        request.start()
    }

    private func handleStoreKitTransaction(_ msg: TransactionUpdate) {
        switch msg {
        case .didChangeStoreFront:
            print(#file, #line, "did change store front")

        case .restoredCompletedTransactions:
            print(#file, #line, "completed transactions finished")
            self.receiptData = .fromLocalReceipt(Current.appBundle)

        case .updatedTransactions(let transactions):
            for transaction in transactions {
                switch transaction.typedTransactionState {
                case .pending(_):
                    break

                case .completed(let completedState):
                    // Fulfills pending purchase result promise.
                    let pendingResult: Result<(), ErrorEvent<IAPError>>
                    defer {
                        let pending = self.pendingPurchasePromises
                            .removeFirstMatching(transaction: transaction)
                        pending?.promise.fulfill(IAPResult(transaction: transaction,
                                                           result: pendingResult))
                    }

                    switch completedState {
                    case let .failure(skError):
                        self.paymenQueue.finishTransaction(transaction)
                        pendingResult = .failure(ErrorEvent(IAPError.storeKitError(skError)))

                    case let .success(success):
                        switch success {
                        case .purchased:
                            pendingResult = .success(())

                            switch try? AppStoreProductType.from(transaction: transaction) {
                            case .none:
                               fatalError("unknown product type \(String(describing: transaction))")
                            case .psiCash:
                                if Current.debugging.immediatelyFinishAllIAPTransaction {
                                    self.paymenQueue.finishTransaction(transaction)
                                }
                                self.state.pendingPsiCashPurchase = transaction
                                self.param.consumableTxObserver.tell(message:
                                    PsiCashConsumableTransaction(transaction: transaction))
                            case .subscription:
                                self.paymenQueue.finishTransaction(transaction)
                            }

                        case .restored:
                            pendingResult = .success(())
                            self.paymenQueue.finishTransaction(transaction)
                        }
                    }
                }
            }

            if transactions.appReceiptUpdated {
                self.receiptData = .fromLocalReceipt(Current.appBundle)
            }
        }
    }

    required init(_ param: Params) {
        self.param = param
        self.state = .init(pendingPsiCashPurchase: nil)

        self.lifetime += SignalProducer.combineLatest(SignalProducer(self.subscriptionActor.output),
                                                      self.$state.signalProducer)
            .map(OutputState.init(subscription:iapState:))
            .start(self.param.pipeOut)
    }

    func preStart() {
        /// According to https://developer.apple.com/documentation/storekit/in-app_purchase/setting_up_the_transaction_observer_and_payment_queue
        /// this observer must be persistent and no deallocated during the app lifecycle.
        self.paymenQueue.add(self.paymentTransactionDelegate)

        // Creates the subscription actor.
        self.subscriptionActor.create(Current.actorBuilder,
                                      parent: self,
                                      transform: id,
                                      propsBuilder: { input in
                                        Props(SubscriptionActor.self,
                                              param: SubscriptionActor.Param(pipeOut: input),
                                              qos: .userInteractive)
        })
        self.receiptData = .fromLocalReceipt(Current.appBundle)
    }

    func postStop() {
        self.paymenQueue.remove(self.paymentTransactionDelegate)
    }

}

/// ActorDelegate for StoreKit transactions.
fileprivate class PaymentTransactionDelegate: ActorDelegate, SKPaymentTransactionObserver {

    // Sent when transactions are removed from the queue (via finishTransaction:).
    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions
        transactions: [SKPaymentTransaction]) {
        // Ignore.
    }

    // Sent when an error is encountered while adding transactions
    // from the user's purchase history back to the queue.
    func paymentQueue(_ queue: SKPaymentQueue,
                      restoreCompletedTransactionsFailedWithError error: Error) {
        actor ! IAPActor.TransactionUpdate.restoredCompletedTransactions(error: error)
    }

    // Sent when all transactions from the user's purchase history have
    // successfully been added back to the queue.
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        actor ! IAPActor.TransactionUpdate.restoredCompletedTransactions(error: .none)
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
        actor ! IAPActor.TransactionUpdate.updatedTransactions(transactions)
    }

    @available(iOS 13.0, *)
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        actor ! IAPActor.TransactionUpdate.didChangeStoreFront
    }

}

/// ActorDelegate for StoreKit receipt refresh request: `SKReceiptRefreshRequest`.
fileprivate class ReceiptRefreshRequestDelegate: ActorDelegate, SKRequestDelegate {

    func requestDidFinish(_ request: SKRequest) {
        actor ! IAPActor.RequestResult.receiptRefreshResult(.success(()))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        let errorEvent = ErrorEvent(error as NSError)
        actor ! IAPActor.RequestResult.receiptRefreshResult(.failure(errorEvent))
    }

}

fileprivate extension Set where Element == PendingPurchase {

    /// Removes the first element that matches `transaction` from the set and returns it.
    mutating func removeFirstMatching(transaction: SKPaymentTransaction)
        -> PendingPurchase? {
        let values = self.filter {
            transaction.payment.isEqual($0.payment)
        }

        guard let element = values.first else {
            return .none
        }
        return self.remove(element)
    }

}
