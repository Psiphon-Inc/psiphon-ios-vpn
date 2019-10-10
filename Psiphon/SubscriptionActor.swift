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
import StoreKit


// TODO!! just delete that dictionary
/// Legacy subscription dictionary
let userDefaultsSubscriptionDictionary = "kSubscriptionDictionary"


infix operator | : TernaryPrecedence

enum SubscriptionState: Equatable {
    case subscribed(SubscriptionData)
    case notSubscribed
    case unknown
}

class SubscriptionActor: Actor {
    typealias ParamType = Param

    struct Param {
        let publisher: ReplaySubject<SubscriptionState>
        let notifier: Notifier
        let sharedDB: PsiphonDataSharedDB
        let userDefaultsConfig: UserDefaultsConfig
    }

    enum Action: AnyMessage {
        case updatedReceiptData(ReceiptData?)
    }

    private enum ResultAction: AnyMessage {
        case timerFinishedWithExpiry(Date)
    }

    /// Timer leeway.
    static let leeway: DispatchTimeInterval = .seconds(10)

    /// Minimum time interval in seconds before the subscription expires
    /// that will trigger a forced subscription check in the network extension.
    static let notifierMinSubDuration: TimeInterval = 60.0

    var context: ActorContext!
    private let param: Param
    private var expiryTimer: SingleFireTimer?
    private var subscriptionData: SubscriptionData?
    private var state: SubscriptionState {
        didSet { param.publisher.onNext(state) }
    }

    required init(_ param: Param) {
        self.param = param
        self.subscriptionData = .none
        self.state = .unknown

        // Sets the initial value of publisher.
        param.publisher.onNext(self.state)
    }

    lazy var receive = behavior { [unowned self] in

        switch $0 {
        case let msg as Action:
            switch msg {

            case .updatedReceiptData(let data):
                updatePersistedData(receipt: data, self.param.sharedDB,
                                    self.param.userDefaultsConfig)

                self.subscriptionData = data?.subscription
                (self.state, self.expiryTimer) = stateGiven(
                    receiptData: data,
                    leeway: Self.leeway,
                    notImmediatleyExpiring: { [unowned self] (intervalToExpired: TimeInterval) in
                        // Asks the extension to perform a subscription check,
                        // only if at least `notifierMinSubDuration` is remaining.
                        if intervalToExpired > Self.notifierMinSubDuration {
                            self.param.notifier.post(NotifierForceSubscriptionCheck)
                        }
                    }, timerFinished: { [unowned self] expiry in
                        self ! ResultAction.timerFinishedWithExpiry(expiry)
                })

                return .same
            }

        case let msg as ResultAction:

            switch msg {
            case .timerFinishedWithExpiry(let expiry):

                /// In case of a race condition where an `.updateSubscription` message is received
                /// immediately before a `.timerFinishedWithExpiry`, the expiration dates
                /// are compared.
                /// If the current subscription data has a later expiry date than the expiry date in
                /// `.timerFinishedWithExpiry` associated value, then we ignore the message.

                guard let subscriptionData = self.subscriptionData else {
                    return .unhandled(msg)
                }

                /// If the current expiry is different from the expiry that the message was sent with.
                if expiry <= subscriptionData.latestExpiry {
                    self.expiryTimer = .none
                    self.state = .notSubscribed
                }
                return .same
            }

        default: return .unhandled($0)
        }
    }

    func postStop() {
        // Cleanup
        self.expiryTimer = .none
    }

}

func stateGiven(receiptData: ReceiptData?,
                leeway: DispatchTimeInterval,
                notImmediatleyExpiring: (TimeInterval) -> Void,
                timerFinished: @escaping (Date) -> Void)-> (SubscriptionState, SingleFireTimer?) {

    guard
        let receiptData = receiptData,
        let subscriptionData = receiptData.subscription
        else {
            return (.notSubscribed, .none)
    }

    let intervalToExpired = subscriptionData.latestExpiry.timeIntervalSinceNow

    guard intervalToExpired > 1 else {
        return (.notSubscribed, .none)
    }

    notImmediatleyExpiring(intervalToExpired)

    let timer = SingleFireTimer(deadline: intervalToExpired, leeway: leeway, queue: .none) {
        timerFinished(subscriptionData.latestExpiry)
    }

    return (.subscribed(subscriptionData), timer)
}

/// Updates `UserDefaultsConfig` and `PsiphonDataSharedDB` based on the data
func updatePersistedData(receipt data: ReceiptData?,
                         _ sharedDB: PsiphonDataSharedDB,
                         _ userDefaultsConfig: UserDefaultsConfig) {

    guard let data = data else {
        sharedDB.setContainerEmptyReceiptFileSize(NSNumber(integerLiteral: 0))
        return
    }

    guard let subscription = data.subscription else {
        sharedDB.setContainerEmptyReceiptFileSize(data.fileSize as NSNumber)
        return
    }

    userDefaultsConfig.subscriptionData = subscription

    // The receipt contains purchase data, reset value in the shared DB.
    sharedDB.setContainerEmptyReceiptFileSize(.none)
    sharedDB.setContainerLastSubscriptionReceiptExpiryDate(subscription.latestExpiry)
}
