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

typealias SubscriptionActorPublisher = ActorPublisher<SubscriptionActor>

class SubscriptionActor: Actor, Publisher {
    typealias PublishedType = State
    typealias ParamType = Param

    struct Param {
        let publisher: ReplaySubject<PublishedType>
    }

    enum Action: AnyMessage {
        case updatedSubscription(SubscriptionData)
        case timerFinished
    }

    enum State: Equatable {
        case subscribed(SubscriptionData)
        case notSubscribed
        case unknown
    }

    var context: ActorContext!
    let param: Param

    var expiryTimer: DispatchSourceTimer?

    var notifObserver: NotificationObserver!
    var subscriptionData: SubscriptionData?
    var state: State {
        didSet { param.publisher.onNext(state) }
    }

    lazy var receive = behavior { [unowned self] in
        guard let msg = $0 as? Action else {
            return .unhandled($0)
        }

        switch msg {
        case .updatedSubscription(let subscriptionData):
            self.subscriptionData = subscriptionData

            // TODO! cancel previous timer if any

            // The timer can have a very large tolerance value.
            let intervalToExpired = subscriptionData.latestExpiry.timeIntervalSinceNow
            if intervalToExpired > 5 {
                self.state = .subscribed(subscriptionData)

                // Asks the extension to perform a forced subscription check.
                Notifier.sharedInstance().post(NotifierForceSubscriptionCheck)

                self.expiryTimer = DispatchSource.makeTimerSource()

                let deadline = DispatchTime.now() + DispatchTimeInterval.seconds(Int(intervalToExpired))

                self.expiryTimer?.schedule(deadline: deadline, repeating: .never, leeway: DispatchTimeInterval.seconds(60 * 10))

                self.expiryTimer?.setEventHandler(handler: {
                    self ! Action.timerFinished
                })


            }

        case .timerFinished:
            break
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

        let data = SubscriptionData.fromSubsriptionDictionary(
            IAPStoreHelper.subscriptionDictionary() as! [String : Any])

        if let data = data {
            self ! Action.updatedSubscription(data)
        }

    }

    func postStop() {
        // TODO! invalidate the timer somehow
//        self.expiryTimer?.invalidate()
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
