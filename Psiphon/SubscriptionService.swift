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

struct SubscriptionProductIds {
    let ids: [String]

    init(plistKey: String) {
        // TODO! validate the strings
        ids = try! plistReader(key: plistKey)
    }
}

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
        case readLocalReceipt
        case updatedSubscription(SubscriptionData)
        case timerFinishedWithExpiry(Date)
    }

    fileprivate enum StoreKitDelegate: AnyMessage {
        case productRequestResponse(SKProductsResponse)
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

    var expiryTimer: SingleFireTimer?

    var notifObserver: NotificationObserver!
    var subscriptionData: SubscriptionData?
    var state: State {
        didSet { param.publisher.onNext(state) }
    }

    var storeProducts = [SKProduct]()

    lazy var receive = behavior { [unowned self] in

        switch $0 {

        case let msg as StoreKitDelegate:

            switch msg {

            case .productRequestResponse(let response):
                self.storeProducts = sortedByPrice(response.products)

            }

        case let msg as Action:

            switch msg {
            case .productRequest(forProducts: let productList):

                break

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
            }

        default: return .unhandled($0)
        }

        return .same
    }

    required init(_ param: Param) {
        self.param = param
        self.subscriptionData = .none
        self.state = .unknown

        // Sets the initial value of publisher.
        param.publisher.onNext(self.state)
    }

    func preStart() {

        // Observes NSNotifications from IAPStoreHelper
        self.notifObserver = NotificationObserver([.IAPHelperUpdatedSubscriptionDictionary])
        { (name: Notification.Name, obj: Any?) in
            switch name {

            case .IAPHelperUpdatedSubscriptionDictionary:
                guard let dict = obj as? [String: Any] else {
                    fatalError("Failed to cast dictionary '\(String(describing: obj))'")
                }

                let data = SubscriptionData.fromSubsriptionDictionary(dict)!
                self ! Action.updatedSubscription(data)

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
        self.expiryTimer = .none
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

fileprivate class SubscriptionActorProductRequestDelegate: NSObject, SKProductsRequestDelegate {

    private unowned let actor: ActorRef

    init(_ actor: ActorRef) {
        self.actor = actor
    }

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        actor ! SubscriptionActor.StoreKitDelegate.productRequestResponse(response)
    }

}

struct SubscriptionData: Equatable {
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
