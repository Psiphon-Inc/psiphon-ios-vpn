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

infix operator < : ComparisonPrecedence
infix operator | : TernaryPrecedence

enum PsiCashActorError: AnyMessage, Error {
    case tunnelNotConnected
}

fileprivate enum PsiCashRefreshResult: AnyMessage {
    /// Successful state refresh result.
    case success
    /// Probable mismatch between client state and the server state.
    case mismatch(PsiCashTransactionMismatchError)
    /// Client tokens are invalid.
    case invalidTokens
    /// Network, server or other critical errors.
    case error(Error)
}

/// `PsiCashTransactionMismatchError` represents errors that are due to state mismatch between
/// the client and the PsiCash server, ignoring programmer error.
/// The client should probably sync its state with the server, and it probably shouldn't retry automatically.
/// The user also probably needs to be informed for an error of this type.
fileprivate enum PsiCashTransactionMismatchError: Error {
    /// Insufficient balance to make the transaction.
    case insufficientBalance
    /// Client has out of date purchase price.
    case transactionAmountMismatch
    /// Client has out of date product list.
    case transactionTypeNotFound
    /// There exists a transaction for the purchase class specified.
    case existingTransaction
}

// TODO! replace this with something else
fileprivate struct PsiCashRemoteRefreshError: Error {
    let errorStatus: PsiCashStatus
}

fileprivate struct PsiCashError: Error {
    let status: PsiCashStatus
    let error: Error?
}

fileprivate struct PsiCashPurchaseResult: AnyMessage {
    let purchase: PsiCashPurchasable
    let result: Result<Purchase, PsiCashError>
}

// MARK: PsiCash Actor

typealias PsiCashActorPublisher = ActorPublisher<PsiCashActor>

class PsiCashActor: Actor, Publisher {
    typealias ParamType = Params
    typealias PublishedType = State

    struct Params {
        let publisher: ReplaySubject<PublishedType>
        let vpnManager: VPNManager
    }

    /// Messages accepted by `PsiCashActor`.
    enum Action: AnyMessage {

        /// Refreshes PsiCash state by syncing with the server.
        /// If not tunneled, sends `PsiCashActorError.tunnelNotConnected` messege to the sender (if any).
        case refreshState

        /// Sends a purchase request for the given purchasable item.
        /// If not tunneled, sends `PsiCashActorError.tunnelNotConnected` messege to the sender (if any).
        case purchase(PsiCashPurchasable)

        /// Replies to sedner with the PsiCash modified URL.
        case modifyLandingPage(RestrictedURL)

        /// Replies to sender with rewarded video custom data as `String?`
        /// Sends nil if there is no custom data at the moment of processing.
        case rewardedVideoCustomData
    }

    struct State: Equatable {
        let lib: PsiCashLibData
        let pendingPurchase: PsiCashPurchasable?
    }

    var context: ActorContext!
    let publisher: ReplaySubject<PublishedType>

    private let vpnManager: VPNManager
    private let sharedDB =
        PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER)
    private let psiCashLib = PsiCash()
    private lazy var logger = PsiCashLogger(client: psiCashLib)

    private var state: State {
        didSet { publisher.onNext(state) }
    }

    required init(_ param: Params) {
        vpnManager = param.vpnManager
        publisher = param.publisher

        let markedExpiredAuthIds = sharedDB.getMarkedExpiredAuthorizationIDs()
        state = State(lib: psiCashLib.dataModel(markedPurchaseAuthIDs: markedExpiredAuthIds),
                    pendingPurchase: nil)
        publisher.onNext(state)
    }

    /// Behavior that only handles `refreshState` and `purchase` messages.
    lazy var tunneledBehavior: Behavior = behavior { [unowned self] in
        guard let action = $0 as? Action else {
            return .unhandled($0)
        }

        /// If tunnel is not connected, sends error message `tunnelNotConnected`
        /// to sender (if any).
        guard case .connected = self.vpnManager.tunnelProviderStatus else {
            self.context.sender()? ! PsiCashActorError.tunnelNotConnected
            return .same
        }

        switch action {
        case .refreshState:
            refreshStateRemote(psicash: self.psiCashLib,
                               andGetPricesFor: PsiCashTransactionClass.allCases,
                               replyTo: self)
            return .new(self.untunneledBehavior)

        case .purchase(let purchasable):
            self.state = map(self.state) {
                return State(lib: $0.lib, pendingPurchase: purchasable)
            }
            purchaseProduct(purchasable,
                            replyTo: self.context.sender()!,
                            psiCashActor: self,
                            psicash: self.psiCashLib,
                            logger: self.logger)
            return .new(self.untunneledBehavior)

        default: return .unhandled(action)
        }
    }

    /// Basic behavior. Handles all messages excpet for messages that contact remote server.
    /// This behavior simply drops `refreshState` and `purchase` messages.
    lazy var untunneledBehavior: Behavior = behavior { [unowned self] in
        switch $0 {
        case let msg as Action:

            switch msg {
            case .refreshState, .purchase:
                // Drops message until `PsiCashRefreshResult` or `PsiCashPurchaseResult`
                // messages are received.
                return .same

            case .modifyLandingPage(let url):
                self.context.sender()! ! addPsiCashToLandingPage(url, psicash: self.psiCashLib,
                                                                 logger: self.logger)
            case .rewardedVideoCustomData:
                self.context.sender()! ! rewardedVideoCustomData(psicash: self.psiCashLib,
                                                                 logger: self.logger)
            }

        case let msg as PsiCashRefreshResult:
            // TODO! what to do with the result.
            return .new(self.allCases)

        case let msg as PsiCashPurchaseResult:

            // TODO!
            // For these last two:
            //   AppDelegate should listen to events emitted from here and react accordingly.
            // 3. Ensure homepage is shown when extension reconnects with new auth token
            // 4. Post the new authorization to the extension

            self.state = map(self.state) { _ in
                State(lib: self.dataModelFromLib(), pendingPurchase: nil)
            }

            return .new(self.allCases)

        default: return .unhandled($0)
        }

        return .same
    }

    lazy var allCases = self.untunneledBehavior | self.tunneledBehavior
    lazy var receive = self.allCases

    func preStart() {
        // TODO! some of these values probably need to repopulated after they've been determined.
        psiCashLib.setRequestMetadata()
    }

    func postStop() {

    }
}

extension PsiCashActor {

    private func dataModelFromLib() -> PsiCashLibData {
        // TODO! is it correct to pass `sharedDB.getMarkedExpiredAuthorizationIDs` to dataModel ?
        psiCashLib.dataModel(markedPurchaseAuthIDs: sharedDB.getMarkedExpiredAuthorizationIDs())
    }

    private func syncSharedDBAuthorizationsWithPsiCashLib() {
        // TODO! maybe this should be taken out of the PsiCashActor.

        sharedDB.setContainerAuthorizations(psiCashLib.speedBoostAuthorizations())
    }

    // TODO! How much do we really need this?
    private func refreshStateLocal() {
        syncSharedDBAuthorizationsWithPsiCashLib()

        // TODO! Commit the model staging area
    }
}

// MARK: PsiCash functions
fileprivate func refreshStateRemote(psicash: PsiCash,
                                    andGetPricesFor priceClasses: [PsiCashTransactionClass],
                                    replyTo: ActorRef) {

    // Updates request metadata before sending the request.
    psicash.setRequestMetadata()

    let purchaseClasses = priceClasses.map { $0.rawValue }
    psicash.refreshState(purchaseClasses) { psiCashStatus, error in
        guard error == nil else {
            replyTo ! PsiCashRefreshResult.error(error!)
            return
        }

        switch psiCashStatus {
        case .success:
            replyTo ! PsiCashRefreshResult.success

        case .existingTransaction:
            replyTo ! PsiCashRefreshResult.mismatch(.existingTransaction)

        case .insufficientBalance:
            replyTo ! PsiCashRefreshResult.mismatch(.insufficientBalance)

        case .transactionAmountMismatch:
            replyTo ! PsiCashRefreshResult.mismatch(.transactionAmountMismatch)

        case .transactionTypeNotFound:
            replyTo ! PsiCashRefreshResult.mismatch(.transactionTypeNotFound)

        case .invalidTokens:
            replyTo ! PsiCashRefreshResult.invalidTokens

        case .invalid, .serverError:
            replyTo ! PsiCashRefreshResult.error(
                PsiCashRemoteRefreshError(errorStatus: psiCashStatus))

        @unknown default:
            preconditionFailure("unknown PsiCash status '\(psiCashStatus)'")
        }
    }
}

fileprivate func purchaseProduct(_ purchasable: PsiCashPurchasable,
                                 replyTo: ActorRef,
                                 psiCashActor: ActorRef,
                                 psicash: PsiCash,
                                 logger: PsiCashLogger) {
    precondition(replyTo !== psiCashActor)

    logger.logEvent("Purchase",
                    withInfo: String(describing: purchasable),
                    includingDiagnosticInfo: false)

    // Updates request metadata before sending the request.
    psicash.setRequestMetadata()

    psicash.newExpiringPurchaseTransaction(
        forClass: purchasable.product.rawTransactionClass,
        withDistinguisher: purchasable.product.distinguisher,
        withExpectedPrice: NSNumber(value: purchasable.price.inNanoPsi))
    { (status: PsiCashStatus, purchase: PsiCashPurchase?, error: Error?) in

        let msg: PsiCashPurchaseResult
        if status == .success {
            msg = PsiCashPurchaseResult(purchase: purchasable,
                                        result: .success(purchase!.mapToPurchase()))
        } else {
            let err = PsiCashError(status: status, error: error)
            msg = PsiCashPurchaseResult(purchase: purchasable,
                                        result: .failure(err))
        }

        // Send the message to self and the actor that requested the purchase.
        psiCashActor ! msg
        replyTo ! msg
    }
}

fileprivate func addPsiCashToLandingPage(_ url: RestrictedURL,
                                         psicash: PsiCash,
                                         logger: PsiCashLogger) -> RestrictedURL {
    return url.map {
        var modifiedURL: NSString?
        let error = psicash.modifyLandingPage($0.absoluteString, modifiedURL: &modifiedURL)
        guard error == nil else {
            logger.logErrorEvent("ModifyURLFailed",
                                 withError: error,
                                 includingDiagnosticInfo: true)
            return url
        }

        guard let value = modifiedURL else {
            logger.logErrorEvent("ModifyURLFailed",
                                 withInfo: "modified URL is nil",
                                 includingDiagnosticInfo: true)
            return url
        }

        return RestrictedURL(URL(string: value as String)!)
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
