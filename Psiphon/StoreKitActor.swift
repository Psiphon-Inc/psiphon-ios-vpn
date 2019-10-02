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

infix operator | : TernaryPrecedence


struct StoreProductIds {
    let ids: Set<String>

    enum ProductIdType: String {
        case subscription = "subscriptionProductIds"
        case psiCash = "psiCashProductIds"
    }

    init(for type: ProductIdType) {
        ids = try! plistReader(key: type.rawValue)
        // TODO! validate the type
    }
}


class StoreKitActor: Actor {
    typealias ParamType = Param

    struct Param {
        let subscriptonActorParam: SubscriptionActor.Param
    }

    enum Action: AnyMessage {
        case productListRequest(for: StoreProductIds)
        case buyProduct(SKProduct)
        case refreshReceipt // TODO!! this is the appStore refresh kind
    }

    fileprivate enum StoreKitResult: AnyMessage {
        case productRequestResult(Result<SKProductsResponse, Error>)
        case receiptRefreshResult(Result<Void, Error>)
    }

    fileprivate enum Transaction: AnyMessage {
        case updatedTransaction(Result<[SKPaymentTransaction], Error>)

        // TODO!! see which one of these is needed?
        case didChangeStoreFront
        case completedTransactionsFinished
        case removedTransactions([SKPaymentTransaction])
    }

    var context: ActorContext!
    let param: Param
    var subscriptionActor: ActorRef!


    // TODO! where should this thing go?
    /// Products available for purchase.
    /// - Note: Products are sorted by price.
    var storeProducts = [SKProduct]()

    private var paymentTransactionDelegate: PaymentTransactionDelegate!

    required init(_ param: Param) {
        self.param = param
    }

    /// Behavior for handling requests to StoreKit.
    lazy var requestsBehavior = behavior { [unowned self] in
        guard let msg = $0 as? Action else {
            return .unhandled($0)
        }

        switch msg {
        case .productListRequest(for: let storeProductIds):
            let responseDelegate = ProductRequestDelegate(replyTo: self)
            let request = SKProductsRequest(productIdentifiers: storeProductIds.ids)
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
        }
    }

    /// Behavior for handling responses from StoreKit requests.
    fileprivate lazy var waitingForRequest =
    { [unowned self] (delegate: ActorDelegate?, msg: AnyMessage) -> Receive in
        switch msg {
        case let msg as Transaction:
            self.handleStoreKitTransaction(msg)

        case let msg as StoreKitResult:
            switch msg {
            case .productRequestResult(let result):
                break
                // TODO! do something with the result.
                //                switch result {
                //                case .success(let response):
                //                    self.storeProducts = sortedByPrice(response.products)
                //                case .failure(let error):
                //                    break
                //                }

            case .receiptRefreshResult(let result):
                break
                // TODO!! do something with the result
                //                switch result {
                //                case .success:
                //                    // TODO! is this necessary here?
                //                    self.updateSubscriptionDictionaryFromLocalReceipt()
                //                case .failure(let error):
                //                    // TODO!! maybe show an error message to the user
                //                    break
                //                }
            }
        default: return .unhandled(msg)
            // TODO!!! this is incorrect, should be .new(self.requestsEnabledBehavior)
        }

        // TODO!! is this correct?
        return .same
    }

    lazy var waitingBehavior = { (delegate: ActorDelegate?) -> Behavior in
        behavior { [unowned self] in
            self.waitingForRequest(delegate, $0)
        }
    }

    lazy var requestEnabledBehavior = self.waitingBehavior(.none) | self.requestsBehavior
    lazy var receive = self.requestEnabledBehavior

    private func handleStoreKitTransaction(_ msg: Transaction) {
        switch msg {

        case .updatedTransaction(let result):
            switch result {
            case .success(let transactions):
                self.handleUpdatedTransaction(transactions)
            case .failure(let error):
                print(#file, "failed updated transactions: \(error)")
            }

        case .didChangeStoreFront:
            print(#file, "did change store front")
        case .completedTransactionsFinished:
            print(#file, "completed transactions finished")
        case .removedTransactions(let transactions):
            print(#file, "removed transactions: \(transactions)")

        }
    }

    private func handleUpdatedTransaction(_ transactions: [SKPaymentTransaction]) {

        // TODO!! is this necessary here?
        //        looks like we're doing it a bit too much
        //        updateSubscriptionDictionaryFromLocalReceipt()

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

    func preStart() {
        // TODO!!! finish this
        /// According to https://developer.apple.com/documentation/storekit/in-app_purchase/setting_up_the_transaction_observer_and_payment_queue
        /// this should be added in AppDelegate didFinishLaunchingWithOptions.
        self.paymentTransactionDelegate = PaymentTransactionDelegate(replyTo: self)
        SKPaymentQueue.default().add(self.paymentTransactionDelegate)

        // Create the subscription actor.
        let props = Props(SubscriptionActor.self,
                          param: self.param.subscriptonActorParam,
                          qos: .userInteractive)

        self.subscriptionActor = context.spawn(props, name: AppActorType.subscription.rawValue)

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

        // TODO!! IAPStoreHelper didn't implement this callback.
        actor ! StoreKitActor.Transaction.removedTransactions(transactions)
    }

    // Sent when an error is encountered while adding transactions from the user's purchase history back to the queue.
    func paymentQueue(_ queue: SKPaymentQueue,
                      restoreCompletedTransactionsFailedWithError error: Error) {

        // TODO!!
        // [self updateSubscriptionDictionaryFromLocalReceipt];
        actor ! StoreKitActor.Transaction.updatedTransaction(.failure(error))
    }

    // Sent when all transactions from the user's purchase history have successfully been added back to the queue.
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        // TODO!!
        // [self updateSubscriptionDictionaryFromLocalReceipt];
        actor ! StoreKitActor.Transaction.completedTransactionsFinished
    }

    // Sent when a user initiates an IAP buy from the App Store
    @available(iOS 11.0, *)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        // TODO!! do we even want to keep this around?
        return false
    }

    // Sent when the transaction array has changed (additions or state changes).  Client should check state of transactions and finish as appropriate.
    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        actor ! StoreKitActor.Transaction.updatedTransaction(.success(transactions))
    }

    @available(iOS 13.0, *)
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        // TODO! check what this does and how we need to react
        actor ! StoreKitActor.Transaction.didChangeStoreFront
    }

}


/// ActorDelegate for StoreKit product request object:`SKProductsRequest`.
fileprivate class ProductRequestDelegate: ActorDelegate, SKProductsRequestDelegate {

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        actor ! StoreKitActor.StoreKitResult.productRequestResult(.success(response))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        actor ! StoreKitActor.StoreKitResult.productRequestResult(.failure(error))
    }

}


/// ActorDelegate for StoreKit receipt refresh request: `SKReceiptRefreshRequest`.
fileprivate class ReceiptRefreshRequestDelegate: ActorDelegate, SKRequestDelegate {

    func requestDidFinish(_ request: SKRequest) {
        actor ! StoreKitActor.StoreKitResult.receiptRefreshResult(.success(()))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        actor ! StoreKitActor.StoreKitResult.receiptRefreshResult(.failure(error))
    }

}


struct ReceiptData: Equatable, Codable {
    let fileSize: Int

    /// Subscription data stored in the receipt.
    /// Nil if no subscription data is found in the receipt.
    let subscription: SubscriptionData?
    // TODO! add consumables here
    // let consumable: Array<Something>

    /// Parses local app receipt and returns a `RceiptData` object.
    /// If no receipt file is found at path pointed to by the `Bundle` `.none` is returned.
    /// - Note: It is expected for the `Bundle` object to have a valid 
    static func fromLocalReceipt(_ appBundle: Bundle) -> ReceiptData? {

        // TODO!! what are the cases where this is nil?
        let receiptURL = appBundle.appStoreReceiptURL!
        let appBundleIdentifier = appBundle.bundleIdentifier!

        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            // TODO!! do something? receipt file doesn't exist. Why was this function called at all?
            return .none
        }
        guard let receiptData = AppStoreReceiptData.parseReceipt(receiptURL) else {
            // TODO!! maybe do something if the parsing fails.
            return .none
        }
        // Validate bundle identifier.
        guard receiptData.bundleIdentifier == appBundleIdentifier else {
            // TODO!! maybe do something if the bundle identifiers don't match
            return .none
        }
        guard let inAppSubscription = receiptData.inAppSubscriptions else {
            return .none
        }
        guard let castedInAppSubscription = inAppSubscription as? [String: Any] else {
            return .none
        }

        let subscriptionData =
            SubscriptionData.fromSubsriptionDictionary(castedInAppSubscription)

        return ReceiptData(fileSize: receiptData.fileSize as! Int,
                           subscription: subscriptionData)
    }

}


// TODO! store and recover this struct instead of the subscription dictionary
struct SubscriptionData: Equatable, Codable {
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
        guard let expiration = dict[ReceiptFields.latestExpirationDate] as? Date else {
            return .none
        }
        guard let productId = dict[ReceiptFields.productId] as? String else {
            return .none
        }
        guard let introPeriod = dict[ReceiptFields.hasBeenInIntroPeriod] as? Bool else {
            return .none
        }
        return SubscriptionData(latestExpiry: expiration, productId: productId,
                                hasBeenInIntroPeriod: introPeriod)
    }
}
