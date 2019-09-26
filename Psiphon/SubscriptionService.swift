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
import SwiftActors
import RxSwift

infix operator | : TernaryPrecedence


typealias SubscriptionActorPublisher = ActorPublisher<SubscriptionActor>

class SubscriptionActor: Actor, Publisher {
    typealias PublishedType = State
    typealias ParamType = Param

    struct Param {
        let publisher: ReplaySubject<PublishedType>
        let notifier: Notifier

        // TODO: This is a temporary workaround,
        // SubscriptionActor should be able to replace all the logic in the IAPStoreHelper.
        let appStoreHelperSubscriptionDict: () -> SubscriptionData?
    }

    enum Action: AnyMessage {
        case productRequest(forProducts: SubscriptionProductIds)
        case buyProduct(SKProduct)
        case refreshReceipt

        case readLocalReceipt
        case updatedSubscription(SubscriptionData)
        case timerFinishedWithExpiry(Date)
    }

    fileprivate enum StoreKitResult: AnyMessage {
        case productRequestResult(Result<SKProductsResponse, Error>)
        case paymentUpdatedTransaction([SKPaymentTransaction])
        case receiptRefreshResult(Result<Void, Error>)
    }

    enum State: Equatable {
        case subscribed(SubscriptionData)
        case notSubscribed
        case unknown
    }

    /// Timer leeway.
    static let leeway: DispatchTimeInterval = .seconds(10)

    /// Minimum time interval in seconds before the subscription expires
    /// that will trigger a forced subscription check in the network extension.
    static let notifierMinSubDuration: TimeInterval = 60.0

    var context: ActorContext!
    let param: Param
    private var paymentTransactionDelegate: PaymentTransactionDelegate!

    var expiryTimer: SingleFireTimer?

    var notifObserver: NotificationObserver!
    var subscriptionData: SubscriptionData?
    var state: State {
        didSet { param.publisher.onNext(state) }
    }

    /// Products available for purchase.
    /// - Note: Products are sorted by price.
    var storeProducts = [SKProduct]()

    required init(_ param: Param) {
        self.param = param
        self.subscriptionData = .none
        self.state = .unknown

        // Sets the initial value of publisher.
        param.publisher.onNext(self.state)
    }

    lazy var requestsBehavior = behavior { [unowned self] in
        guard let msg = $0 as? Action else {
            return .unhandled($0)
        }

        switch msg {
        case .productRequest(forProducts: let products):
            let responseDelegate = ProductRequestDelegate(replyTo: self)
            let request = SKProductsRequest(productIdentifiers: products.ids)
            request.delegate = responseDelegate
            request.start()
            return .new(self.waitingBehavior(responseDelegate))

        case .buyProduct(let product):
            let payment = SKPayment(product: product)
            SKPaymentQueue.default().add(payment)
            return .new(self.waitingBehavior(.none))

        case .refreshReceipt:
            let responseDelegate = ReceiptRefreshRequestDelegate(replyTo: self)
            let request = SKReceiptRefreshRequest()
            request.delegate = responseDelegate
            request.start()
            return .new(self.waitingBehavior(responseDelegate))

        default: return .unhandled(msg)
        }
    }

    fileprivate lazy var waitingForRequest =
    { [unowned self] (delegate: ActorDelegate?, msg: AnyMessage) -> Receive in
        switch msg {

        case let msg as StoreKitResult:
            switch msg {
            case .productRequestResult(let result):
                switch result {
                case .success(let response):
                    self.storeProducts = sortedByPrice(response.products)
                case .failure(let error):
                    break
                }

            case .paymentUpdatedTransaction(let transactions):
                self.handleUpdatedTransaction(transactions)

            case .receiptRefreshResult(let result):
                switch result {
                case .success:
                    // TODO! is this necessary here?
                    self.updateSubscriptionDictionaryFromLocalReceipt()
                case .failure(let error):
                    // TODO!! maybe show an error message to the user
                    break
                }
            }
            // TODO!!! this is incorrect, should be .new(self.requestsEnabledBehavior)
            return .same

        case let msg as Action:
            switch msg {
            case .productRequest(_): return .same
            case .buyProduct(_): return .same // TODO!! or maybe should not handle
            case .refreshReceipt:
                self.updateSubscriptionDictionaryFromLocalReceipt()

            case .updatedSubscription(let newData):
                guard self.subscriptionData != newData else {
                    return .same
                }

                self.subscriptionData = newData

                (self.state, self.expiryTimer) = timerFrom(
                    subscriptionData: newData,
                    extensionForcedCheck: { (intervalToExpired: TimeInterval) in
                        // Asks the extension to perform a subscription check,
                        // only if at least `notifierMinSubDuration` is remaining.
                        if intervalToExpired > Self.notifierMinSubDuration {
                            self.param.notifier.post(NotifierForceSubscriptionCheck)
                        }
                    },
                    timerFinished: { [unowned self] in
                        self ! Action.timerFinishedWithExpiry(newData.latestExpiry)

                    })

            case .timerFinishedWithExpiry(let expiry):

                /// In case of a race condition where an `.updateSubscription` message is received
                /// immediately before a `.timerFinishedWithExpiry`, the expiration dates
                /// are compared.
                /// If the current subscription data has a later expiry date than the expiry date in
                /// `.timerFinishedWithExpiry` associated value, then we ignore the message.

                guard let subscriptionData = self.subscriptionData else {
                    return .unhandled(msg)
                }

                if expiry <= subscriptionData.latestExpiry {
                    self.expiryTimer = .none
                    self.state = .notSubscribed
                }
            case .readLocalReceipt:
                // TODO! implement this
                break

            }

        default: return .unhandled(msg)
        }

        return .same
    }

    lazy var waitingBehavior = { (delegate: ActorDelegate?) -> Behavior in
        behavior { [unowned self] in
            self.waitingForRequest(delegate, $0)
        }
    }

    lazy var requestEnabledBehavior = self.waitingBehavior(.none) | self.requestsBehavior
    lazy var receive = self.requestEnabledBehavior

    func preStart() {

        // TODO!!! finish this
        /// According to https://developer.apple.com/documentation/storekit/in-app_purchase/setting_up_the_transaction_observer_and_payment_queue
        /// this should be added in AppDelegate didFinishLaunchingWithOptions.
        self.paymentTransactionDelegate = PaymentTransactionDelegate(replyTo: self)
        SKPaymentQueue.default().add(self.paymentTransactionDelegate)

        // TODO!! remove this one IAPStoreHelper has been ported over.
        // Observes NSNotifications from IAPStoreHelper
        self.notifObserver = NotificationObserver([.IAPHelperUpdatedSubscriptionDictionary])
        { (name: Notification.Name, obj: Any?) in
            switch name {

            case .IAPHelperUpdatedSubscriptionDictionary:
                guard let dict = obj as? [String: Any]? else {
                    fatalError("failed to cast dictionary '\(String(describing: obj))'")
                }

                if let dict = dict {
                    let data = SubscriptionData.fromSubsriptionDictionary(dict)!
                    self ! Action.updatedSubscription(data)
                }

            default:
                fatalError("Unhandled notification \(name)")
            }

        }

        // Updates actor's internal subscription data after subscribing to
        // `IAPHelperUpdatedSubscriptionDictionary`.
        if let data = param.appStoreHelperSubscriptionDict() {
            self ! Action.updatedSubscription(data)
        }

    }

    func postStop() {
        // Cleanup
        self.expiryTimer = .none
        SKPaymentQueue.default().remove(self.paymentTransactionDelegate)
    }

    func handleUpdatedTransaction(_ transactions: [SKPaymentTransaction]) {

        // TODO!! is this necessary here?
        //        looks like we're doing it a bit too much
        updateSubscriptionDictionaryFromLocalReceipt()

        for transaction in transactions {
            switch transaction.transactionState {
            case .purchasing:
                break
            case .deferred:
                break
            case .purchased:
                SKPaymentQueue.default().finishTransaction(transaction)
            case .failed:
                // TODO!! use the error property to present a message to the user.
//                let error = transaction.error
                SKPaymentQueue.default().finishTransaction(transaction)
            case .restored:
                SKPaymentQueue.default().finishTransaction(transaction)
            @unknown default:
                assertionFailure("unknown transaction state \(transaction.transactionState)")
            }
        }

    }

    func updateSubscriptionDictionaryFromLocalReceipt() {
        // TODO!! implement this
    }
}


/// - Parameter timerFinished: Called when the timer finishes
func timerFrom(subscriptionData: SubscriptionData,
                      extensionForcedCheck: (TimeInterval) -> Void,
                      timerFinished: @escaping () -> Void) -> (SubscriptionActor.State, SingleFireTimer?) {

    // Since subscriptions are in days/months/years,
    // the timer can have a large tolerance value.
    let intervalToExpired = subscriptionData.latestExpiry.timeIntervalSinceNow

    guard intervalToExpired > 1 else {
        return (.notSubscribed, .none)
    }

    extensionForcedCheck(intervalToExpired)

    let timer = SingleFireTimer(deadline: intervalToExpired, leeway: SubscriptionActor.leeway, timerFinished)
    return (.subscribed(subscriptionData), timer)
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
    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        // TODO!! IAPStoreHelper didn't implement this callback.
    }


    // Sent when an error is encountered while adding transactions from the user's purchase history back to the queue.
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        // TODO!!
        // [self updateSubscriptionDictionaryFromLocalReceipt];
    }

    // Sent when all transactions from the user's purchase history have successfully been added back to the queue.
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        // TODO!!
        // [self updateSubscriptionDictionaryFromLocalReceipt];
    }

    // Sent when the download state has changed.
    @available(iOS 6.0, *)
    func paymentQueue(_ queue: SKPaymentQueue, updatedDownloads downloads: [SKDownload]) {
        // TODO!! this function is not even interesting to us.
    }

    // Sent when a user initiates an IAP buy from the App Store
    @available(iOS 11.0, *)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {

        // TODO! although we don't allow buying directly from the AppStore anyways
        return true
    }

    // Sent when the transaction array has changed (additions or state changes).  Client should check state of transactions and finish as appropriate.
    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        actor ! SubscriptionActor.StoreKitResult.paymentUpdatedTransaction(transactions)
    }

    @available(iOS 13.0, *)
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        // TODO! check what this does and how we need to react
    }

}


/// ActorDelegate for StoreKit product request object:`SKProductsRequest`.
fileprivate class ProductRequestDelegate: ActorDelegate, SKProductsRequestDelegate {

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        actor ! SubscriptionActor.StoreKitResult.productRequestResult(.success(response))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        actor ! SubscriptionActor.StoreKitResult.productRequestResult(.failure(error))
    }

}


/// ActorDelegate for StoreKit receipt refresh request: `SKReceiptRefreshRequest`.
fileprivate class ReceiptRefreshRequestDelegate: ActorDelegate, SKRequestDelegate {

    func requestDidFinish(_ request: SKRequest) {
        actor ! SubscriptionActor.StoreKitResult.receiptRefreshResult(.success(()))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        actor ! SubscriptionActor.StoreKitResult.receiptRefreshResult(.failure(error))
    }

}


/// Validated subscription product identifiers.
struct SubscriptionProductIds {
    let ids: Set<String>

    init(plistKey: String) {
        // TODO! validate the strings
        ids = try! plistReader(key: plistKey)
    }
}


// TODO! store and recover this struct instead of the subscription dictionary
struct SubscriptionData: Equatable, Codable {
    let receiptSize: Int
    let latestExpiry: Date
    let productId: String
    let hasBeenInIntroPeriod: Bool

    // Enum values match dictionary keys defined in "IAPStoreHelper.h"
    private enum ReceiptFields: String {
        case appReceiptFileSize = "app_receipt_file_size"
        case latestExpirationDate = "latest_expiration_date"
        case productId = "product_id"
        case hasBeenInIntroPeriod = "has_been_in_intro_period"
    }

    static func fromSubsriptionDictionary(_ dict: [String: Any]) -> SubscriptionData? {
        guard let size = dict[ReceiptFields.appReceiptFileSize] as? Int else {
            return .none
        }
        guard let expiration = dict[ReceiptFields.latestExpirationDate] as? Date else {
            return .none
        }
        guard let productId = dict[ReceiptFields.productId] as? String else {
            return .none
        }
        guard let introPeriod = dict[ReceiptFields.hasBeenInIntroPeriod] as? Bool else {
            return .none
        }

        return SubscriptionData(receiptSize: size, latestExpiry: expiration,
                                   productId: productId, hasBeenInIntroPeriod: introPeriod)
    }

}
