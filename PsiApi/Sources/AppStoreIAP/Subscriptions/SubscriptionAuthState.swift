/*
 * Copyright (c) 2020, Psiphon Inc.
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
import ReactiveSwift
import PsiApi

/// Represents authorization state for subscription purchase.
public struct SubscriptionPurchaseAuthState: Hashable, Codable {
    
    public enum AuthorizationState: Hashable {

        public enum RequestRejectedReason: String, Codable, CaseIterable {
            /// Received 400-Bad Request error from the purchase verifier server.
            case badRequestError
            /// Transaction had expired.
            case transactionExpired
            /// Transaction has been cancelled by Apple customer service.
            case transactionCancelled
        }
        
        /// Authorization not requested for the current transaction.
        case notRequested
        
        /// Authorization request failed. Authorization request can be retried again later.
        case requestError(ErrorEvent<ErrorRepr>)
        
        /// Authorization request rejected by the purchase verifier server.
        /// Authorization request should **not** be retried for this transaction anymore.
        /// If receipt is refreshed by the App Store, the transaction can be retried.
        case requestRejected(RequestRejectedReason)
        
        /// Retrieved an authorization successfully.
        case authorization(SignedData<SignedAuthorization>)
        
        /// Authorization rejected by the Psiphon servers.
        /// If the transaction has not expired, another authorization can be requested from the purchase verifier server.
        case rejectedByPsiphon(SignedData<SignedAuthorization>)
    }
    
    /// Subscription purchase contained in the app receipt.
    public let purchase: SubscriptionIAPPurchase
    
    /// State of authorization for the `purchase`.
    public var signedAuthorization: AuthorizationState

}

public enum SubscriptionAuthStateAction {
    
    public enum StoredDataUpdateType {
        case didUpdateRejectedSubscriptionAuthIDs
        case didRefreshReceiptData(ReceiptReadReason)
    }

    case localDataUpdate(type: StoredDataUpdateType)
    
    case _didLoadStoredPurchaseAuthState(
        loadResult: Result<SubscriptionAuthState.PurchaseAuthStateDict, SystemErrorEvent<Int>>,
        replayDataUpdate: StoredDataUpdateType?
    )
    
    case _requestAuthorizationForPurchases
    
    case _localDataUpdateResult(
        transformer: (SubscriptionAuthState.PurchaseAuthStateDict) ->
            (SubscriptionAuthState.PurchaseAuthStateDict, [Effect<SubscriptionAuthStateAction>])
    )
    
    case _authorizationRequestResult(
        result: RetriableTunneledHttpRequest<SubscriptionValidationResponse>.RequestResult,
        forPurchase: SubscriptionIAPPurchase
    )
}

public struct SubscriptionAuthStateReducerEnvironment {
    public let feedbackLogger: FeedbackLogger
    public let httpClient: HTTPClient
    public let httpRequestRetryCount: Int
    public let httpRequestRetryInterval: DispatchTimeInterval
    public let notifier: Notifier
    public let notifierUpdatedSubscriptionAuthsMessage: String
    public let sharedDB: SharedDBContainer
    public let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    public let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    public let clientMetaData: () -> ClientMetaData
    public let dateCompare: DateCompare

    public init(feedbackLogger: FeedbackLogger, httpClient: HTTPClient,
               httpRequestRetryCount: Int, httpRequestRetryInterval: DispatchTimeInterval,
               notifier: Notifier, notifierUpdatedSubscriptionAuthsMessage: String,
               sharedDB: SharedDBContainer,
               tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
               tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
               clientMetaData: @escaping () -> ClientMetaData,
               dateCompare: DateCompare) {

        self.feedbackLogger = feedbackLogger
        self.httpClient = httpClient
        self.httpRequestRetryCount = httpRequestRetryCount
        self.httpRequestRetryInterval = httpRequestRetryInterval
        self.notifier = notifier
        self.notifierUpdatedSubscriptionAuthsMessage = notifierUpdatedSubscriptionAuthsMessage
        self.sharedDB = sharedDB
        self.tunnelStatusSignal = tunnelStatusSignal
        self.tunnelConnectionRefSignal = tunnelConnectionRefSignal
        self.clientMetaData = clientMetaData
        self.dateCompare = dateCompare
    }
}

public struct SubscriptionAuthState: Equatable {

    public init() {}
    
    public typealias PurchaseAuthStateDict = [WebOrderLineItemID: SubscriptionPurchaseAuthState]

    /// Set of transactions that either have a pending authorization request (either in-flight or pending tunnel connected).
    public var transactionsPendingAuthRequest = Set<WebOrderLineItemID>()
    
    /// `nil` represents that subscription auths have not been restored from previously stored value.
    /// This value is in  sync with stored value in  `PsiphonDataSharedDBContainer`
    /// with key `subscription_authorizations_dict`.
    public var purchasesAuthState: PurchaseAuthStateDict? = .none
}

public struct SubscriptionReducerState: Equatable {

    public var subscription: SubscriptionAuthState

    let receiptData: ReceiptData?

    public init(subscription: SubscriptionAuthState, receiptData: ReceiptData?)  {
        self.subscription = subscription
        self.receiptData = receiptData
    }

}

public let subscriptionAuthStateReducer = Reducer<SubscriptionReducerState
                                                  , SubscriptionAuthStateAction
                                                  , SubscriptionAuthStateReducerEnvironment> {
    state, action, environment in

    switch action {
    
    case .localDataUpdate(type: let updateType):
        guard let receiptData = state.receiptData else {
            return [
                Effect(value:
                    ._didLoadStoredPurchaseAuthState(
                        loadResult: .success([:]),
                        replayDataUpdate: .none
                    )
                )
            ]
        }
        
        guard state.subscription.purchasesAuthState != nil else {
            return [
                StoredSubscriptionPurchasesAuthState.getValue(sharedDB: environment.sharedDB)
                    .map {
                        ._didLoadStoredPurchaseAuthState(
                            loadResult: $0,
                            replayDataUpdate: updateType
                        )
                }
            ]
        }
        
        let receiptInAppPurchases = receiptData.subscriptionInAppPurchases
        
        return [
            StoredRejectedSubscriptionAuthIDs.getValue(sharedDB: environment.sharedDB)
                .map { rejectedAuthIDsSeqTuple -> SubscriptionAuthStateAction in
                    ._localDataUpdateResult { current in
                        
                        var effects = [Effect<SubscriptionAuthStateAction>]()
                        
                        // Merges subscription purchases present in the receipt,
                        // with `current` data for the given purchases.
                        var newValue = current.merge(withUpdatedPurchases: receiptInAppPurchases)
                        
                        // If the receipt is refreshed from the App Store,
                        // resets authorization state to `.notRequested`, for any
                        // purchase whose authorization request result in 400-Bad request error.
                        if case .didRefreshReceiptData(let readReason) = updateType {
                            newValue = newValue.resetAuthorizationBadRequest(
                                forReceiptUpdateType: readReason
                            )
                        }
                        
                        // Updates authorization state for any purchase that had it's authorization
                        // rejected by Psiphon servers.
                        newValue = newValue.updateAuthorizationState(
                            givenRejectedAuthIDs: rejectedAuthIDsSeqTuple.rejectedValues
                        )
                        
                        effects += StoredRejectedSubscriptionAuthIDs
                            .setContainerReadRejectedAuthIDs(
                                atLeastUpToSequenceNumber: rejectedAuthIDsSeqTuple.writeSeqNumber,
                                sharedDB: environment.sharedDB)
                            .fireAndForget()
                        
                        return (newValue, effects)
                    }
                }
        ]
        
    case let ._didLoadStoredPurchaseAuthState(loadResult: loadResult, replayDataUpdate: updateType):
        switch loadResult {
        case .success(let loadedValue):
            var effects = [Effect<SubscriptionAuthStateAction>]()
            
            effects += state.subscription
                .setPurchasesAuthState(newValue: loadedValue,
                                       environment: environment)
                .mapNever()
            
            // Replays `localDataUpdate(type:)` action if not nil.
            if let updateType = updateType {
                effects += Effect(value: .localDataUpdate(type: updateType))
            }
            
            return effects
            
        case .failure(let errorEvent):
            // Reading from PsiphonDataSharedDBContainer failed.
            // Resets value of stored subscription purchase auth state.
            
            let stateUpdateEffect = state.subscription.setPurchasesAuthState(
                newValue: [:],
                environment: environment
            )
            
            return [
                stateUpdateEffect.then(
                    Effect(value: .localDataUpdate(type: .didRefreshReceiptData(.localRefresh)))
                ),
                
                environment.feedbackLogger.log(.error, "failed reading stored subscription auth state '\(errorEvent)'")
                    .mapNever()
            ]
        }
        
    case ._localDataUpdateResult(transformer: let transformerFunc):
        guard let currentPurchasesAuthState = state.subscription.purchasesAuthState else {
            fatalError()
        }

        let (newValue, effects) = transformerFunc(currentPurchasesAuthState)
        
        // Avoids duplicate updates if there has been no value change.
        guard newValue != currentPurchasesAuthState else {
            return effects + [
                Effect(value: ._requestAuthorizationForPurchases)
            ]
        }

        let stateUpdateEffect = state.subscription.setPurchasesAuthState(
            newValue: newValue,
            environment: environment
        )

        return effects + [
            stateUpdateEffect.mapNever(),
            Effect(value: ._requestAuthorizationForPurchases)
        ]
        
    case ._requestAuthorizationForPurchases:
        guard let receiptData = state.receiptData else {
            return []
        }
        
        // Filters `purchasesAuthState` for purchases that do not have an authorization,
        // or an authorization request could be retried.
        let purchasesWithoutAuth = state.subscription.purchasesAuthState?.values.filter {
            $0.canRequestAuthorization(dateCompare: environment.dateCompare)
        }
        
        let sortedByExpiry = purchasesWithoutAuth?.sorted(by: {
            $0.purchase.expires < $1.purchase.expires
        })
        
        // Authorization is only retrieved for purchase with the latest expiry.
        guard let purchaseWithLatestExpiry = sortedByExpiry?.last else {
            return []
        }
        
        // If the transaction is expired according to device's clock
        let isExpired = purchaseWithLatestExpiry.purchase
            .isApproximatelyExpired(environment.dateCompare)
        
        guard !isExpired else {
            return []
        }
        
        // Adds transaction ID to set of transaction IDs pending authorization request response.
        let (inserted, _) = state.subscription.transactionsPendingAuthRequest.insert(
            purchaseWithLatestExpiry.purchase.webOrderLineItemID
        )
        
        // Guards that the an authorization request is not already made given the transaction ID.
        guard inserted else {
            return []
        }

        // Creates retriable authorization request.

        let req = PurchaseVerifierServer.subscription(
            requestBody: SubscriptionValidationRequest(
                originalTransactionID: purchaseWithLatestExpiry.purchase.originalTransactionID,
                webOrderLineItemID: purchaseWithLatestExpiry.purchase.webOrderLineItemID,
                productID: purchaseWithLatestExpiry.purchase.productID,
                receipt: receiptData
            ),
            clientMetaData: environment.clientMetaData()
        )

        let authRequest = RetriableTunneledHttpRequest(
            request: req.request,
            retryCount: environment.httpRequestRetryCount,
            retryInterval: environment.httpRequestRetryInterval
        )

        var effects = [Effect<SubscriptionAuthStateAction>]()

        if let error = req.error {
            effects += [environment.feedbackLogger.log(.error,
                                                       tag: "SubscriptionAuthStateReducer._requestAuthorizationForPurchases",
                                                       error).mapNever()]
        }
        
        return effects + [
            authRequest(
                getCurrentTime: environment.dateCompare.getCurrentTime,
                tunnelStatusSignal: environment.tunnelStatusSignal,
                tunnelConnectionRefSignal: environment.tunnelConnectionRefSignal,
                httpClient: environment.httpClient
            ).map {
                ._authorizationRequestResult(
                    result: $0,
                    forPurchase: purchaseWithLatestExpiry.purchase
                )
            },
            environment.feedbackLogger.log(.info, """
                initiated auth request for webOrderLineItemID \
                \(purchaseWithLatestExpiry.purchase.webOrderLineItemID)
                """).mapNever()
        ]
        
    case let ._authorizationRequestResult(result: requestResult, forPurchase: purchase):
        guard
            state.subscription.transactionsPendingAuthRequest
                .contains(purchase.webOrderLineItemID)
            else {
                return [
                    environment.feedbackLogger.log(.warn, """
                        'state.subscription.transactionsPendingAuthRequest' does not contains \
                        purchase with webOrderLineItemID: '\(purchase.webOrderLineItemID)'
                        """).mapNever()
                ]
        }
        
        guard let purchasesAuthState = state.subscription.purchasesAuthState else {
            fatalError()
        }
        
        guard purchasesAuthState.contains(webOrderLineItemID: purchase.webOrderLineItemID)
            else {
                
                // Removes the transaction from set of transactions pending auth request,
                // as this transaction is no longer valid (since it is not part of the state).
                state.subscription.transactionsPendingAuthRequest
                    .remove(purchase.webOrderLineItemID)
                
                return [
                    environment.feedbackLogger.log(.warn, """
                        'state.subscription.purchaseAuthStates' does not contain purchase
                        with webOrderLineItemID: '\(purchase.webOrderLineItemID)'
                        """).mapNever()
                ]
        }
        
        switch requestResult {
        case .willRetry(when: let retryCondition):
            switch retryCondition {
            case .whenResolved(tunnelError: .nilTunnelProviderManager):
                return [ environment.feedbackLogger.log(.error, retryCondition).mapNever() ]
                
            case .whenResolved(tunnelError: .tunnelNotConnected):
                // This event is too frequent to log.
                return []
                
            case .afterTimeInterval:
                return [ environment.feedbackLogger.log(.error, retryCondition).mapNever() ]
            }
            
        case .failed(let errorEvent):
            // Authorization request finished in failure.
            
            var effects = [Effect<SubscriptionAuthStateAction>]()
            
            effects += environment.feedbackLogger
                .log(.error, "authorization request failed '\(errorEvent)'").mapNever()
            
            // Authorization request for this purchase is no longer pending.
            state.subscription.transactionsPendingAuthRequest.remove(purchase.webOrderLineItemID)
            
            let stateUpdateEffect = state.subscription.setAuthorizationState(
                newValue: .requestError(errorEvent.eraseToRepr()),
                forWebOrderLineItemID: purchase.webOrderLineItemID,
                environment: environment
            )
            
            effects += stateUpdateEffect.mapNever()
            
            return effects
            
        case .completed(let subscriptionValidationResult):
            // Authorization request completed with a response from purchase verifier server.
            
            // Authorization request for this purchase is no longer pending.
            state.subscription.transactionsPendingAuthRequest.remove(purchase.webOrderLineItemID)
            
            switch subscriptionValidationResult {
                
            case .success(let okResponse):
                // 200-OK response from the purchase verifier server.
                guard okResponse.webOrderLineItemID == purchase.webOrderLineItemID else {
                    let log: LogMessage =
                        """
                        sever webOrderLineItemID '\(okResponse.webOrderLineItemID)' did not match \
                        expected webOrderLineItemID '\(purchase.webOrderLineItemID)'
                        """
                    let err = ErrorEvent(ErrorRepr(repr:String(describing:log)),
                                         date: okResponse.requestDate)
                    return [
                        state.subscription.setAuthorizationState(
                            newValue: .requestError(err),
                            forWebOrderLineItemID: purchase.webOrderLineItemID,
                            environment: environment
                        ).mapNever(),
                        environment.feedbackLogger.log(.error, log).mapNever()
                    ]
                }
                
                switch okResponse.errorStatus {
                case .noError:
                    guard let signedAuthorization = okResponse.signedAuthorization else {
                        let log: LogMessage = "expected 'signed_authorization' in response '\(okResponse)'"
                        let err = ErrorEvent(ErrorRepr(repr:String(describing:log)),
                                             date: okResponse.requestDate)
                        return [
                            state.subscription.setAuthorizationState(
                                newValue: .requestError(err),
                                forWebOrderLineItemID: purchase.webOrderLineItemID,
                                environment: environment
                            ).mapNever(),
                            environment.feedbackLogger.log(.error, log).mapNever()
                        ]
                    }
                    
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .authorization(signedAuthorization),
                        forWebOrderLineItemID: okResponse.webOrderLineItemID,
                        environment: environment
                    )
                    
                    return [
                        stateUpdateEffect.mapNever(),
                        environment.feedbackLogger.log(.info, """
                            authorization request completed with auth id \
                            '\(signedAuthorization.decoded.authorization.id)' expiring on \
                            '\(signedAuthorization.decoded.authorization.expires)'
                            """
                        ).mapNever()
                    ]
                    
                case .transactionExpired:
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .requestRejected(.transactionExpired),
                        forWebOrderLineItemID: okResponse.webOrderLineItemID,
                        environment: environment
                    )
                    
                    return [
                        stateUpdateEffect.mapNever(),
                        environment.feedbackLogger.log(.error, """
                            authorization request completed with error \
                            '\(okResponse.errorDescription)'
                            """).mapNever()
                    ]
                    
                case .transactionCancelled:
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .requestRejected(.transactionCancelled),
                        forWebOrderLineItemID: okResponse.webOrderLineItemID,
                        environment: environment
                    )
                    
                    return [
                        stateUpdateEffect.mapNever(),
                        environment.feedbackLogger.log(.error, """
                            authorization request completed with error \
                            '\(okResponse.errorDescription)'
                            """).mapNever()
                    ]
                }
                
            case .failure(let failureEvent):
                // Non-200 OK response from the purchase verifier server.
                var effects = [Effect<SubscriptionAuthStateAction>]()
                
                effects += environment.feedbackLogger.log(.error, """
                        authorization request failed for webOrderLineItemID \
                        '\(purchase.webOrderLineItemID)': error: '\(failureEvent)'
                        """).mapNever()
                
                if case .badRequest = failureEvent.error {
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .requestRejected(.badRequestError),
                        forWebOrderLineItemID: purchase.webOrderLineItemID,
                        environment: environment
                    )
                    
                    effects += stateUpdateEffect.mapNever()
                    
                } else {
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .requestError(failureEvent.eraseToRepr()),
                        forWebOrderLineItemID: purchase.webOrderLineItemID,
                        environment: environment
                    )
                    
                    effects += stateUpdateEffect.mapNever()
                }
                
                return effects
            }
        }
    }
}

// MARK: Type extensions

extension SubscriptionStatus {
    
    var isSubscribed: Bool {
        switch self {
        case .subscribed(_): return true
        case .notSubscribed: return false
        case .unknown: return false
        }
    }
    
}

extension Dictionary where Key == WebOrderLineItemID, Value == SubscriptionPurchaseAuthState {
    
    func updateAuthorizationState(
        givenRejectedAuthIDs rejectedAuthIDs: Set<AuthorizationID>
    ) -> Self {
        self.mapValues { currentValue in
            
            guard case let .authorization(signedAuth) = currentValue.signedAuthorization else {
                return currentValue
            }
            
            guard rejectedAuthIDs.contains(signedAuth.decoded.authorization.id) else {
                return currentValue
            }
            
            return SubscriptionPurchaseAuthState(
                purchase: currentValue.purchase,
                signedAuthorization: .rejectedByPsiphon(signedAuth)
            )
        }
    }
    
    /// Resets the authorization state of transactions that resulted in a 400-Bad Request error
    /// from the purchase verifier server.
    /// The refreshed receipt should prevent future bad request errors.
    /// Note: Transaction IDs are regenerated after subscription is restored.
    func resetAuthorizationBadRequest(forReceiptUpdateType updateType: ReceiptReadReason) -> Self {
        switch updateType {
        case .localRefresh:
            // Do nothing
            return self
            
        case .remoteRefresh:
            return self.mapValues { currentValue in
                
                switch currentValue.signedAuthorization {
                case .requestRejected(.badRequestError):
                    return SubscriptionPurchaseAuthState(
                        purchase: currentValue.purchase,
                        signedAuthorization: .notRequested
                    )
                default:
                    return currentValue
                }
                
            }
        }
    }
    
    /// Creates a new dictionary from from given `updatedPurchases`.
    /// All transaction are copied from `updatedPurchases`, however `signedAuthorization`
    /// and `rejectedByPsiphon` values copied from self if the same transaction exists.
    /// If the same transaction is not in `self`, then authorization state is set to `.notRequested`.
    /// - Precondition: Each element `updatedPurchases` must have unique transaction ID.
    func merge(withUpdatedPurchases updatedPurchases: Set<SubscriptionIAPPurchase>) -> Self {
        
        // updatedPurchases with latest expiry, hashed by WebOrderLineItemID.
        let altUpdatedPurchases = Set(updatedPurchases.sortedByExpiry().reversed().map {
            HashableView($0, \.webOrderLineItemID)
        })

        let updatedPurchasesDict = [WebOrderLineItemID: SubscriptionIAPPurchase](
            uniqueKeysWithValues: altUpdatedPurchases.map {
                ($0.value.webOrderLineItemID, $0.value)
            }
        )
        return updatedPurchasesDict.mapValues {
            SubscriptionPurchaseAuthState(
                purchase: $0,
                signedAuthorization: self[$0.webOrderLineItemID]?.signedAuthorization ?? .notRequested
            )
        }
    }
    
    func contains(webOrderLineItemID: WebOrderLineItemID) -> Bool {
        self.contains { (key, _) -> Bool in
            key == webOrderLineItemID
        }
    }
    
}

extension SubscriptionPurchaseAuthState {
    
    /// `canRequestAuthorization` determines whether an authorization request could be sent to the purchase verifier
    /// server based on the current state of `signedAuthorization`, and device clock.
    func canRequestAuthorization(dateCompare: DateCompare) -> Bool {
        switch self.signedAuthorization {
        case .notRequested:
            return true
        case .requestError(_):
            return true
        case .requestRejected(_):
            return false
        case .authorization(_):
            return false
        case .rejectedByPsiphon(_):
            let isExpired = self.purchase.isApproximatelyExpired(dateCompare)
            return !isExpired
        }
    }
    
}

/// State update functions.
extension SubscriptionAuthState {
    
    mutating func setAuthorizationState(
        newValue: SubscriptionPurchaseAuthState.AuthorizationState,
        forWebOrderLineItemID webOrderLineItemID: WebOrderLineItemID,
        environment: SubscriptionAuthStateReducerEnvironment
    ) -> Effect<Never> {
        guard var purchasesAuthState = self.purchasesAuthState else {
            fatalError()
        }
        
        guard var currentValue = purchasesAuthState.removeValue(forKey: webOrderLineItemID) else{
            fatalError("expected webOrderLineItemID '\(webOrderLineItemID)'")
        }
        
        currentValue.signedAuthorization = newValue
        purchasesAuthState[webOrderLineItemID] = currentValue
        return setPurchasesAuthState(newValue: purchasesAuthState, environment: environment)
    }
    
    mutating func setPurchasesAuthState(
        newValue: PurchaseAuthStateDict,
        environment: SubscriptionAuthStateReducerEnvironment
    ) -> Effect<Never> {
        
        defer {
            self.purchasesAuthState = newValue
        }
        
        guard self.purchasesAuthState != nil else {
            return .empty
        }
        
        return StoredSubscriptionPurchasesAuthState.setValue(
                sharedDB: environment.sharedDB, value: newValue
            ).then(
                .fireAndForget {
					environment.notifier.post(environment.notifierUpdatedSubscriptionAuthsMessage)
                }
            )
    }
    
}

// MARK: Effects

fileprivate enum StoredRejectedSubscriptionAuthIDs {
    
    static func getValue(
        sharedDB: SharedDBContainer
    ) -> Effect<(rejectedValues: Set<AuthorizationID>, writeSeqNumber: Int)> {
        Effect { () -> (rejectedValues: Set<AuthorizationID>, writeSeqNumber: Int) in
            
            // Sequence number is read before reading the rejected auth ID values.
            // This is important because we do not have any atomicity guarantee.
            //
            // What could go wrong is described in the following steps:
            // 1. Container reads rejected Auth IDs.
            // 2. Extension updates sequence number and rejected subscription auth IDs.
            // 3. Container reads updated sequence number, but now holds stale rejected Auth IDs.
            
            let lastWriteSeq = sharedDB.getExtensionRejectedSubscriptionAuthIdWriteSequenceNumber()
            
            return (rejectedValues: Set(sharedDB.getRejectedSubscriptionAuthorizationIDs()),
                    writeSeqNumber: lastWriteSeq)
        }
    }
    
    static func setContainerReadRejectedAuthIDs(
        atLeastUpToSequenceNumber seq: Int, sharedDB: SharedDBContainer
    ) -> Effect<()> {
        Effect { () -> Void in
            sharedDB.setContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber(seq)
        }
    }
    
}

fileprivate enum StoredSubscriptionPurchasesAuthState {
    
    typealias StoredDataType = SubscriptionAuthState.PurchaseAuthStateDict
    
    /// Returned effect emits stored data with type `[WebOrderLineItemID, SubscriptionPurchaseAuthState]`.
    /// If there is no stored data, returns an empty dictionary.
    static func getValue(
        sharedDB: SharedDBContainer
    ) -> Effect<Result<StoredDataType, SystemErrorEvent<Int>>> {
        Effect { () -> Result<StoredDataType, SystemErrorEvent<Int>> in
            guard let data = sharedDB.getSubscriptionAuths() else {
                return .success([:])
            }
            do {
                let decoded = try JSONDecoder.makeRfc3339Decoder()
                    .decode(StoredDataType.self, from: data)
                return .success(decoded)
            } catch {
                return .failure(SystemErrorEvent(SystemError<Int>.make(error as NSError), date: Date()))
            }
        }
    }
    
    /// Encodes `value` and stores the `Data` in `sharedDB`.
    static func setValue(
        sharedDB: SharedDBContainer, value: StoredDataType
    ) -> Effect<Result<(), SystemErrorEvent<Int>>> {
        Effect { () -> Result<(), SystemErrorEvent<Int>> in
            do {
                guard !value.isEmpty else {
                    sharedDB.setSubscriptionAuths(nil)
                    return .success(())
                }
                let data = try JSONEncoder.makeRfc3339Encoder().encode(value)
                sharedDB.setSubscriptionAuths(data)
                return .success(())
            } catch {
                return .failure(SystemErrorEvent(SystemError<Int>.make(error as NSError), date: Date()))
            }
        }
    }
    
}
