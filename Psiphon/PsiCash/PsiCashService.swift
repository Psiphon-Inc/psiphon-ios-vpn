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

/// A result that is progressing towards completion. It can either be inProgress, or completed with `Result` associated value.
enum ProgressiveResult<Success, Failure> where Failure: Error {
    /// Result is in progress.
    case inProgress
    /// A failure, storing a `Failure` value.
    case completed(Result<Success, Failure>)
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

// MARK: PsiCashService Actor

class PsiCashService: Actor, Publisher {
    typealias PublishedType = Data

    /// Messages accepted by `PsiCashService`.
    enum Action: AnyMessage {
        case refreshState
        case purchase(PsiCashPurchasable)
        case addPsiCashToLandingPage(NSURL)
        case rewardedVideoCustomData
    }

    struct Data: Equatable {
        let lib: PsiCashLibData
        let pendingPurchase: PsiCashPurchasable?
    }

    var context: ActorContext!
    var didChange = ReplaySubject<PublishedType>.create(bufferSize: 1)

    private var remoteRequestSender: Actor?
    private let sharedDB: PsiphonDataSharedDB
    private let psicash = PsiCash()
    private lazy var logger = PsiCashLogger(client: psicash)

    private var data: Data {
        didSet { didChange.onNext(data) }
    }

    init() {
        sharedDB = PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER)

        let markedExpiredAuthIds = sharedDB.getMarkedExpiredAuthorizationIDs()
        data = Data(lib: psicash.dataModel(markedPurchaseAuthIDs: markedExpiredAuthIds),
                    pendingPurchase: nil)
    }

    /// Actor behavior that only handles `refreshState` and `purchase` messages.
    lazy var withRemote: Behavior = behavior { [unowned self] in
        guard let action = $0 as? Action else {
            return .unhandled($0)
        }

        switch action {
        case .refreshState:
            self.remoteRequestSender = self.context.sender()!
            self.refreshStateRemote(andGetPricesFor: PsiCashTransactionClass.allCases)
            return .new(self.noRemote)

        case .purchase(let purchasable):
            self.remoteRequestSender = self.context.sender()!
            self.data = new(self.data) {
                precondition($0.pendingPurchase == nil,
                             "pendingPurchases is not nil '\(String(describing: $0.pendingPurchase))'")
                return Data(lib: $0.lib, pendingPurchase: purchasable)
            }
            self.purchaseProduct(purchasable)
            return .new(self.noRemote)

        default: return .unhandled(action)
        }
    }

    /// Basic actor behavior. Handles all messages excpet for messages that contact remote server.
    /// This behavior simply drops `refreshState` and `purchase` messages.
    lazy var noRemote: Behavior = behavior { [unowned self] in
        switch $0 {
        case let msg as Action:

            switch msg {
            case .refreshState, .purchase:
                // Drops message until `PsiCashRefreshResult` or `PsiCashPurchaseResult`
                // messages are received.
                return .same

            case .addPsiCashToLandingPage(let url):
                self.context.sender()! ! self.addPsiCashToLandingPage(url)

            case .rewardedVideoCustomData:
                self.context.sender()! ! self.rewardedVideoCustomData()
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

            defer {
                self.remoteRequestSender = nil
            }

            self.data = new(self.data) {
                precondition($0.pendingPurchase != nil)
                return Data(lib: self.dataModelFromLib(), pendingPurchase: nil)
            }

            self.remoteRequestSender! ! msg

            return .new(self.allCases)

        default: return .unhandled($0)
        }

        return .same
    }

    lazy var allCases = self.noRemote | self.withRemote
    lazy var receive = self.allCases

    func preStart() {
        // TODO! some of these values probably need to repopulated after they've been determined.
        psicash.setRequestMetadata()
    }

    private func refreshStateRemote(andGetPricesFor priceClasses: [PsiCashTransactionClass]) {

        // Updates request metadata before sending the request.
        psicash.setRequestMetadata()

        let purchaseClasses = priceClasses.map { $0.rawValue }
        psicash.refreshState(purchaseClasses) { psiCashStatus, error in
            guard error == nil else {
                self ! PsiCashRefreshResult.error(error!)
                return
            }

            switch psiCashStatus {
            case .success:
                self ! PsiCashRefreshResult.success

            case .existingTransaction:
                self ! PsiCashRefreshResult.mismatch(.existingTransaction)

            case .insufficientBalance:
                self ! PsiCashRefreshResult.mismatch(.insufficientBalance)

            case .transactionAmountMismatch:
                self ! PsiCashRefreshResult.mismatch(.transactionAmountMismatch)

            case .transactionTypeNotFound:
                self ! PsiCashRefreshResult.mismatch(.transactionTypeNotFound)

            case .invalidTokens:
                self ! PsiCashRefreshResult.invalidTokens

            case .invalid, .serverError:
                self ! PsiCashRefreshResult.error(
                    PsiCashRemoteRefreshError(errorStatus: psiCashStatus))

            @unknown default:
                preconditionFailure("unknown PsiCash status '\(psiCashStatus)'")
            }
        }
    }

    private func purchaseProduct(_ purchasable: PsiCashPurchasable) {

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
            if status == .success {
                self ! PsiCashPurchaseResult(purchase: purchasable,
                                             result: .success(purchase!.mapToPurchase()))

            } else {
                let err = PsiCashError(status: status, error: error)
                self ! PsiCashPurchaseResult(purchase: purchasable,
                                             result: .failure(err))
            }
        }
    }

    private func addPsiCashToLandingPage(_ url: NSURL) -> NSURL {
        var modifiedURL: NSString?
        let error = psicash.modifyLandingPage(url.absoluteString!, modifiedURL: &modifiedURL)

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

        return NSURL(string: value as String)!
    }

    private func rewardedVideoCustomData() -> String? {
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

}

// Helper methods.
extension PsiCashService {

    private func dataModelFromLib() -> PsiCashLibData {
        // TODO! is it correct to pass `sharedDB.getMarkedExpiredAuthorizationIDs` to dataModel ?
        psicash.dataModel(markedPurchaseAuthIDs: sharedDB.getMarkedExpiredAuthorizationIDs())
    }

    private func syncSharedDBAuthorizationsWithPsiCashLib() {
        // TODO! maybe this should be taken out of the PsiCashService.

        sharedDB.setContainerAuthorizations(psicash.speedBoostAuthorizations())
    }

    // TODO! How much do we really need this?
    private func refreshStateLocal() {
        syncSharedDBAuthorizationsWithPsiCashLib()

        // TODO! Commit the model staging area
    }
}
