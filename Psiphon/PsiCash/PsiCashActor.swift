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
import Promises
import ReactiveSwift

// TODO: Some errors here can probably be combined.

enum PsiCashPurchaseResponseError: HashableError {
    case tunnelNotConnected
    case parseError(PsiCashParseError)
    case serverError(PsiCashStatus, SystemError?)
}

enum PsiCashRefreshError: HashableError {
    /// Refresh request is rejected due to tunnel not connected.
    case tunnelNotConnected
    /// Server has returnd 500 error response.
    /// (PsiCash v1.3.1-0-gd1471c1) the request has already been retried internally and any further retry should not be immediate/
    case serverError
    /// Tokens passed in are invalid.
    /// (PsiCash  v1.3.1-0-gd1471c1) Should never happen. The local user ID will be cleared.
    case invalidTokens
    /// Some other error.
    case error(SystemError)
}

/// `PsiCashTransactionMismatchError` represents errors that are due to state mismatch between
/// the client and the PsiCash server, ignoring programmer error.
/// The client should probably sync its state with the server, and it probably shouldn't retry automatically.
/// The user also probably needs to be informed for an error of this type.
enum PsiCashTransactionMismatchError: HashableError {
    /// Insufficient balance to make the transaction.
    case insufficientBalance
    /// Client has out of date purchase price.
    case transactionAmountMismatch
    /// Client has out of date product list.
    case transactionTypeNotFound
    /// There exists a transaction for the purchase class specified.
    case existingTransaction
}

enum RefreshReason {
    case tunnelConnected
    case appForegrounded
    case rewardedVideoAd
    case psiCashIAP
    case other
}

struct BalanceState: Equatable {
    enum RefreshState: Int, Equatable {
        case refreshing
        case refreshed
        /// Indicates an expected increase in PsiCash balance after next sync with the PsiCash server.
        case waitingForExpectedIncrease
    }
    var refreshState: RefreshState
    /// Balance with expected rewrad amount added.
    /// - Note: This value is either equal to `PsiCashLibData.balance`, or higher if there is expected reward amount.
    var balance: PsiCashAmount
}

struct PsiCashPurchaseResult: Equatable {
    let purchasable: PsiCashPurchasableType
    let purchasedResult: Result<PsiCashPurchasedType, ErrorEvent<PsiCashPurchaseResponseError>>
}

// MARK: PsiCash Actor

final class PsiCashActor: Actor, OutputProtocol, TypedInput {
    typealias OutputType = State
    typealias OutputErrorType = Never
    typealias InputType = Action

    struct Params {
        let initiallySubscribed: Bool
        let pipeOut: Signal<OutputType, OutputErrorType>.Observer
    }

    enum Action: Message {
        case `public`(PublicAction)
        case `internal`(RequestResult)
    }

    /// Messages accepted by `PsiCashActor`.
    enum PublicAction: Message {
        /// Refreshes PsiCash state by syncing with the server.
        /// If not tunneled, sends `PsiCashActorError.tunnelNotConnected` messege to the sender (if any).
        case refreshState(reason: RefreshReason,
            promise: Promise<Result<(), ErrorEvent<PsiCashRefreshError>>>?)

        /// Sends a purchase request for the given purchasable item.
        /// If not tunneled, sends `PsiCashActorError.tunnelNotConnected` messege to the sender (if any).
        case purchase(PsiCashPurchasableType, Promise<PsiCashPurchaseResult>)

        /// Fulfills the promise with the PsiCash modified URL.
        case modifyLandingPage(RestrictedURL, Promise<RestrictedURL>)

        /// Fulfills the promise with rewarded video custom data, if any.
        case rewardedVideoCustomData(Promise<CustomData?>)

        case receivedRewardedVideoReward(amount: PsiCashAmount)

        /// Notifies the actor that there's a pending (not finalized) IAP.
        case pendingPsiCashIAP

        /// Signals that the  user subscription status has changed.
        case userSubscription(Bool)
    }

    enum RequestResult: AnyMessage {
        case refreshStateResult(Result<(), ErrorEvent<PsiCashRefreshError>>)
        case psiCashProductPurchaseResult(PsiCashPurchaseResult)
    }

    struct State: Equatable {
        var libData: PsiCashLibData
        var balanceState: BalanceState
        var pendingPurchase: PsiCashPurchasableType?
    }

    var context: ActorContext!
    private let (lifetime, token) = Lifetime.make()
    private let psiCashLib = PsiCash()
    private lazy var logger = PsiCashLogger(client: psiCashLib)
    private var userSubscribed: Bool
    @ActorState private var state: State

    // TODO: Current behavior composition operators `<>` and `<|>` do not enable the refresh state
    // logic to be easily implemented with the help of `promiseAccumulator`
    // Hence we take a more manual approach of accumulating the promises in an array in this actor,
    // and fulfulling them all once the result of the action has been received.
    private var pendingRefreshStatePromises = [Promise<Result<(), ErrorEvent<PsiCashRefreshError>>>]()

    /// Drops all messages if `userSubscribed` evaluates to true.
    private lazy var subscribedHandler = Action.handler { [unowned self] msg in
        switch msg {
        case .public(.userSubscription(let subscribed)):
            self.userSubscribed = subscribed
            return .same
        default:
            // Drops message if user is subscribed.
            if self.userSubscribed {
                return .same
            } else {
                return .unhandled
            }
        }
    }

    /// Behavior that only handles `refreshState` and `purchase` messages.
    private lazy var tunneledHandler = Action.handler { [unowned self] msg in

        guard case .public(let msg) = msg else {
            return .unhandled
        }

        /// If tunnel is not connected, fulfills the promises with failure.
        /// Next behavior does not change and is still `tunneledHandler`.
        guard Current.tunneled else {
            switch msg {
            case let .refreshState(reason, maybePromise):
                if reason.expectsBalanceIncrease {
                    self.state.balanceState = .waitingForExpectedIncrease(
                        withAddedReward: .zero(), libData: self.state.libData)
                }

                maybePromise?.fulfill(.failure(ErrorEvent(.tunnelNotConnected)))
                return .same

            case .purchase(let purchasableType, let promise):
                promise.fulfill(
                    PsiCashPurchaseResult(purchasable: purchasableType,
                                          purchasedResult: .failure(ErrorEvent(.tunnelNotConnected))))
                return .same
            default: return .unhandled
            }
        }

        switch msg {
        case let .refreshState(reason, maybePromise):
            if self.pendingRefreshStatePromises.count == 0 {
                self.state.balanceState = .refreshing(withAddedReward: .zero(),
                                                      libData: self.state.libData)
                refreshStateRemote(psicash: self.psiCashLib,
                                   andGetPricesFor: PsiCashTransactionClass.allCases,
                                   replyTo: self.typedSelf.projection({ Action.internal($0) }))

            }

            if let promise = maybePromise {
                self.pendingRefreshStatePromises.append(promise)
            }

            return .same

        case .purchase(let purchasable, let promise):
            self.state.pendingPurchase = purchasable
            purchaseProduct(purchasable,
                            replyTo: self.typedSelf.projection({ Action.internal($0) }),
                            psicash: self.psiCashLib,
                            logger: self.logger,
                            fulfill: promise)
            return .same

        default: return .unhandled
        }
    }

    /// Basic behavior. Handles all messages excpet for messages that contact remote server.
    /// This behavior simply drops `refreshState` and `purchase` messages.
    private lazy var untunneledHandler: ActionHandler =
        Action.handler(Action.pull(self.publicMessageHandler(message:),
                                   self.internalMessageHandler(message:)))

    lazy var receive = self.untunneledHandler <|> self.tunneledHandler <|> self.subscribedHandler

    required init(_ param: Params) {
        // Removes any stale purchases from PsiCash library before setting the first state value.
        let sharedDBAuthIds = Current.sharedDB.getNonSubscriptionAuthorizations().map(\.id)
        self.psiCashLib.expirePurchases(notFoundIn: sharedDBAuthIds)
        self.userSubscribed = param.initiallySubscribed
        self.state = State.fromExpectedUserReward(libData: psiCashLib.dataModel())
        self.$state.setPassthrough(param.pipeOut)

        if Current.debugging.psiCashDevServer {
            self.psiCashLib.setValue("dev-api.psi.cash", forKey: "serverHostname")
        }
    }

    func preStart() {
        psiCashLib.setRequestMetadata()

        // Maps connected events to refresh state messages sent to self.
        lifetime += Current.vpnStatus.signalProducer
            .skipRepeats()
            .filter { $0 == .connected }
            .map(value: Action.public(.refreshState(reason: .tunnelConnected, promise: nil)))
            .tell(actor: self.typedSelf)
    }

    func publicMessageHandler(message: PublicAction) -> ActionResult {
        switch message {
        case .refreshState(_, _), .purchase:
            // Drops message until `PsiCashRefreshResult` or `PsiCashPurchaseResult`
            // messages are received.
            return .same

        case .modifyLandingPage(let url, let promise):
            // TODO: Observable lifetime issue
            // Check if subscription is disposed once completed
            // Check if observable is ever completed.
            self.$state.signalProducer
                .map(\.libData.authPackage.hasEarnerToken)
                .falseIfNotTrue(within: .seconds(5))
                .startWithValues { _ in
                    promise.fulfill(addPsiCashToLandingPage(url, psicash: self.psiCashLib,
                                                            logger: self.logger))
            }
            return .same

        case .rewardedVideoCustomData(let promise):
            promise.fulfill(rewardedVideoCustomData(psicash: self.psiCashLib,
                                                    logger: self.logger))
            return .same

        case .pendingPsiCashIAP:
            self.state.balanceState = .waitingForExpectedIncrease(withAddedReward: .zero(),
                                                                  libData: self.state.libData)
            return .same

        case .receivedRewardedVideoReward(let amount):
            self.state.balanceState = .waitingForExpectedIncrease(withAddedReward: amount,
                                                                  libData: self.state.libData)
            return .same

        case .userSubscription(_):
            return .unhandled
        }
    }

    func internalMessageHandler(message: RequestResult) -> ActionResult {
        switch message {
        case .refreshStateResult(let result):
            // Updates state
            self.state.refreshed(libData: self.psiCashLib.dataModel())

            // Fulfill all refresh state pending promises.
            for promise in self.pendingRefreshStatePromises {
                promise.fulfill(result)
            }
            self.pendingRefreshStatePromises = []
            return .same

        case .psiCashProductPurchaseResult(let result):
            switch result.purchasedResult {
            case let .success(purchaseType):
                // Updates `PsiphonDataSharedDB` with updated PsiCash library authorizations,
                // and notifies the extension.
                switch purchaseType {
                case .speedBoost(let purchasedProduct):
                    // TODO: SpeedBoost always has authorization. Fix product struct type
                    // to convery that information, and remove force unwrapping of optional.
                    Current.sharedDB.appendNonSubscriptionAuthorization(
                        purchasedProduct.transaction.authorization)
                    Notifier.sharedInstance().post(NotifierUpdatedNonSubscriptionAuths)
                }

                self.state.resolvedPendingPurchase(libData: self.psiCashLib.dataModel())

            case let .failure(errorEvent):
                // No automatic retries made for product purchase.
                PsiFeedbackLogger.error(withType: "PsiCashActor",
                                        message: "psicash product purchase failed",
                                        object: errorEvent)
            }

            return .same
        }
    }

}

// MARK: PsiCash functions

fileprivate func refreshStateRemote(psicash: PsiCash,
                                    andGetPricesFor priceClasses: [PsiCashTransactionClass],
                                    replyTo: TypedActor<PsiCashActor.RequestResult>) {

    // Updates request metadata before sending the request.
    psicash.setRequestMetadata()

    let purchaseClasses = priceClasses.map { $0.rawValue }
    psicash.refreshState(purchaseClasses) { psiCashStatus, error in
        guard error == nil else {
            replyTo ! .refreshStateResult(.failure(
                ErrorEvent(.error(error! as SystemError))))
            return
        }

        switch psiCashStatus {
        case .success:
            replyTo ! .refreshStateResult(.success(()))

        case .serverError:
            replyTo ! .refreshStateResult(.failure(ErrorEvent(.serverError)))

        case .invalidTokens:
            replyTo ! .refreshStateResult(.failure(
                ErrorEvent(.invalidTokens)))

        default:
            preconditionFailure("unknown PsiCash status '\(psiCashStatus)'")
        }
    }
}

fileprivate func purchaseProduct(_ purchasableType: PsiCashPurchasableType,
                                 replyTo: TypedActor<PsiCashActor.RequestResult>,
                                 psicash: PsiCash,
                                 logger: PsiCashLogger,
                                 fulfill promise: Promise<PsiCashPurchaseResult>) {

    logger.logEvent("Purchase",
                    withInfo: String(describing: purchasableType),
                    includingDiagnosticInfo: false)

    // Updates request metadata before sending the request.
    psicash.setRequestMetadata()

    psicash.newExpiringPurchaseTransaction(
        forClass: purchasableType.rawTransactionClass,
        withDistinguisher: purchasableType.distinguisher,
        withExpectedPrice: NSNumber(value: purchasableType.price.inNanoPsi))
    { (status: PsiCashStatus, purchase: PsiCashPurchase?, error: Error?) in

        let result: PsiCashPurchaseResult
        if status == .success, let purchase = purchase {
            result = PsiCashPurchaseResult(
                purchasable: purchasableType,
                purchasedResult: purchase.mapToPurchased().mapError {
                    ErrorEvent(PsiCashPurchaseResponseError.parseError($0))
            })

        } else {
            result = PsiCashPurchaseResult(
                purchasable: purchasableType,
                purchasedResult: .failure(ErrorEvent(.serverError(status, error as SystemError?)))
            )
        }

        // Send the message to self and fulfill the promise.
        replyTo ! .psiCashProductPurchaseResult(result)
        promise.fulfill(result)
    }
}

fileprivate func addPsiCashToLandingPage(_ restrictedURL: RestrictedURL,
                                         psicash: PsiCash,
                                         logger: PsiCashLogger) -> RestrictedURL {
    return restrictedURL.map { url in
        var maybeModifiedURL: NSString?
        let error = psicash.modifyLandingPage(url.absoluteString, modifiedURL: &maybeModifiedURL)
        guard error == nil else {
            logger.logErrorEvent("ModifyURLFailed",
                                 withError: error,
                                 includingDiagnosticInfo: true)
            return url
        }

        guard let modifiedURL = maybeModifiedURL else {
            logger.logErrorEvent("ModifyURLFailed",
                                 withInfo: "modified URL is nil",
                                 includingDiagnosticInfo: true)
            return url
        }

        return URL(string: modifiedURL as String)!
    }
}

fileprivate func rewardedVideoCustomData(psicash: PsiCash, logger: PsiCashLogger) -> String? {
    var s: NSString?
    let error = psicash.getRewardedActivityData(&s)

    guard error == nil else {
        logger.logErrorEvent("GetRewardedActivityDataFailed",
                             withError: error,
                             includingDiagnosticInfo: true)
        return nil
    }

    return s as String?
}

// MARK: Extensions

extension PsiCashActor.State {
    // Returns the first Speed Boost product that has not expired.
    var activeSpeedBoost: PurchasedExpirableProduct<SpeedBoostProduct>? {
        let activeSpeedBoosts = libData.activePurchases.items
            .compactMap { $0.speedBoost }
            .filter { !$0.transaction.expired }
        return activeSpeedBoosts[maybe: 0]
    }
}

fileprivate extension PsiCashPurchaseResult {

    var shouldRetry: Bool {
        guard case let .failure(errorEvent) = self.purchasedResult else {
            return false
        }
        switch errorEvent.error {
        case .tunnelNotConnected: return false
        case .parseError(_): return false
        case let .serverError(psiCashStatus, _):
            switch psiCashStatus {
            case .invalid, .serverError:
                return true
            case .success, .existingTransaction, .insufficientBalance, .transactionAmountMismatch,
                 .transactionTypeNotFound, .invalidTokens:
                return false
            @unknown default:
                return false
            }
        }
    }

}

fileprivate extension BalanceState {
    static func fromStoredExpectedReward(libData: PsiCashLibData) -> Self {
        let reward = Current.userConfigs.expectedPsiCashReward
        if reward.isZero {
            return .init(refreshState: .refreshed,
                         balance: libData.balance)
        } else {
            return .init(refreshState: .waitingForExpectedIncrease,
                         balance: libData.balance + reward)
        }
    }

    static func refreshed(refreshedData libData: PsiCashLibData) -> Self {
        Current.userConfigs.expectedPsiCashReward = PsiCashAmount.zero()
        return .init(refreshState: .refreshed, balance: libData.balance)
    }

    static func refreshing(withAddedReward added: PsiCashAmount, libData: PsiCashLibData) -> Self {
        return .from(state: .refreshing, addedReward: added, libData: libData)
    }

    static func waitingForExpectedIncrease(withAddedReward added: PsiCashAmount,
                                           libData: PsiCashLibData) -> Self {
        return .from(state: .waitingForExpectedIncrease, addedReward: added, libData: libData)
    }

    private static func from(state: RefreshState, addedReward: PsiCashAmount,
                             libData: PsiCashLibData) -> Self {
        if addedReward > .zero() {
            let newRewardAmount = Current.userConfigs.expectedPsiCashReward + addedReward
            Current.userConfigs.expectedPsiCashReward = newRewardAmount
            return .init(refreshState: state, balance: libData.balance + newRewardAmount)
        } else {
            return .init(refreshState: state, balance: libData.balance)
        }
    }
}

fileprivate extension PsiCashActor.State {

    static func fromExpectedUserReward(libData: PsiCashLibData) -> Self {
        return .init(libData: libData,
                     balanceState: BalanceState.fromStoredExpectedReward(libData: libData),
                     pendingPurchase: nil)
    }

    mutating func refreshed(libData: PsiCashLibData) {
        self.libData = libData
        self.balanceState = .refreshed(refreshedData: libData)
    }

    /// Updates `State` after a success or unsuccessful purchase result data.
    mutating func resolvedPendingPurchase(libData: PsiCashLibData) {
        self.libData =  libData
        self.balanceState = .refreshed(refreshedData: libData)
        self.pendingPurchase = nil
    }
}
