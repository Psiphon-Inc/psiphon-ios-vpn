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
        loadResult: Result<SubscriptionAuthState.PurchaseAuthStateDict, SystemErrorEvent>,
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
    public let clientMetaData: ClientMetaData
    public let getCurrentTime: () -> Date
    public let compareDates: (Date, Date, Calendar.Component) -> ComparisonResult

    public init(feedbackLogger: FeedbackLogger, httpClient: HTTPClient,
               httpRequestRetryCount: Int, httpRequestRetryInterval: DispatchTimeInterval,
               notifier: Notifier, notifierUpdatedSubscriptionAuthsMessage: String,
               sharedDB: SharedDBContainer,
               tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
               tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
               clientMetaData: ClientMetaData,
               getCurrentTime: @escaping () -> Date,
               compareDates: @escaping (Date, Date, Calendar.Component) -> ComparisonResult) {

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
        self.getCurrentTime = getCurrentTime
        self.compareDates = compareDates
    }
}

public struct SubscriptionAuthState: Equatable {

    public init() {}
    
    public typealias PurchaseAuthStateDict = [OriginalTransactionID: SubscriptionPurchaseAuthState]

    /// Set of transactions that either have a pending authorization request (either in-flight or pending tunnel connected).
    public var transactionsPendingAuthRequest = Set<OriginalTransactionID>()
    
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

public func subscriptionAuthStateReducer(
    state: inout SubscriptionReducerState, action: SubscriptionAuthStateAction,
    environment: SubscriptionAuthStateReducerEnvironment
) -> [Effect<SubscriptionAuthStateAction>] {
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
                        
                        effects.append(
                            StoredRejectedSubscriptionAuthIDs.setContainerReadRejectedAuthIDs(
                                atLeastUpToSequenceNumber: rejectedAuthIDsSeqTuple.writeSeqNumber,
                                sharedDB: environment.sharedDB
                            ).fireAndForget()
                        )
                        
                        return (newValue, effects)
                    }
                }
        ]
        
    case let ._didLoadStoredPurchaseAuthState(loadResult: loadResult, replayDataUpdate: updateType):
        switch loadResult {
        case .success(let loadedValue):
            var effects = [Effect<SubscriptionAuthStateAction>]()
            
            effects.append(
                state.subscription.setPurchasesAuthState(
                    newValue: loadedValue,
                    environment: environment
                ).mapNever()
            )
            
            // Replays `localDataUpdate(type:)` action if not nil.
            if let updateType = updateType {
                effects.append(Effect(value: .localDataUpdate(type: updateType)))
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
            $0.canRequestAuthorization(
                getCurrentTime: environment.getCurrentTime,
                compareDates: environment.compareDates
            )
        }
        
        let sortedByExpiry = purchasesWithoutAuth?.sorted(by: {
            $0.purchase.expires < $1.purchase.expires
        })
        
        // Authorization is only retrieved for purchase with the latest expiry.
        guard let purchaseWithLatestExpiry = sortedByExpiry?.last else {
            return []
        }
        
        // If the transaction is expired according to device's clock
        let isExpired = purchaseWithLatestExpiry.purchase.isApproximatelyExpired(
            getCurrentTime: environment.getCurrentTime,
            compareDates: environment.compareDates
        )
        guard !isExpired else {
            return []
        }
        
        // Adds transaction ID to set of transaction IDs pending authorization request response.
        let (inserted, _) = state.subscription.transactionsPendingAuthRequest.insert(
            purchaseWithLatestExpiry.purchase.originalTransactionID
        )
        
        // Guards that the an authorization request is not already made given the transaction ID.
        guard inserted else {
            return []
        }

        // Creates retriable authorization request.

        let req = PurchaseVerifierServer.subscription(
         requestBody: SubscriptionValidationRequest(
             originalTransactionID: purchaseWithLatestExpiry.purchase.originalTransactionID,
             receipt: receiptData
         ),
         clientMetaData: environment.clientMetaData
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
            authRequest.callAsFunction(
                getCurrentTime: environment.getCurrentTime,
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
                initiated auth request for original transaction ID \
                \(purchaseWithLatestExpiry.purchase.originalTransactionID)
                """).mapNever()
        ]
        
    case let ._authorizationRequestResult(result: requestResult, forPurchase: purchase):
        guard
            state.subscription.transactionsPendingAuthRequest
                .contains(purchase.originalTransactionID)
            else {
                return [
                    environment.feedbackLogger.log(.warn, """
                        'state.subscription.transactionsPendingAuthRequest' does not contains \
                        purchase with original transaction ID: '\(purchase.originalTransactionID)'
                        """).mapNever()
                ]
        }
        
        guard let purchasesAuthState = state.subscription.purchasesAuthState else {
            fatalError()
        }
        
        guard purchasesAuthState.contains(originalTransactionID: purchase.originalTransactionID)
            else {
                
                // Removes the transaction from set of transactions pending auth request,
                // as this transaction is no longer valid (since it is not part of the state).
                state.subscription.transactionsPendingAuthRequest
                    .remove(purchase.originalTransactionID)
                
                return [
                    environment.feedbackLogger.log(.warn, """
                        'state.subscription.purchaseAuthStates' does not contain purchase
                        with original transaction ID: '\(purchase.originalTransactionID)'
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
            effects.append(
                environment.feedbackLogger.log(.error, "authorization request failed '\(errorEvent)'").mapNever()
            )
            
            // Authorization request for this purchase is no longer pending.
            state.subscription.transactionsPendingAuthRequest.remove(purchase.originalTransactionID)
            
            let stateUpdateEffect = state.subscription.setAuthorizationState(
                newValue: .requestError(errorEvent.eraseToRepr()),
                forOriginalTransactionID: purchase.originalTransactionID,
                environment: environment
            )
            
            effects.append(
                stateUpdateEffect.mapNever()
            )
            
            return effects
            
        case .completed(let subscriptionValidationResult):
            // Authorization request completed with a response from purchase verifier server.
            
            // Authorization request for this purchase is no longer pending.
            state.subscription.transactionsPendingAuthRequest.remove(purchase.originalTransactionID)
            
            switch subscriptionValidationResult {
                
            case .success(let okResponse):
                // 200-OK response from the purchase verifier server.
                guard okResponse.originalTransactionID == purchase.originalTransactionID else {
                    let log: LogMessage =
                        """
                        sever transaction ID '\(okResponse.originalTransactionID)' did not match \
                        expected transaction ID '\(purchase.originalTransactionID)'
                        """
                    let err = ErrorEvent(ErrorRepr(repr:String(describing:log)),
                                         date: okResponse.requestDate)
                    return [
                        state.subscription.setAuthorizationState(
                            newValue: .requestError(err),
                            forOriginalTransactionID: purchase.originalTransactionID,
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
                                forOriginalTransactionID: purchase.originalTransactionID,
                                environment: environment
                            ).mapNever(),
                            environment.feedbackLogger.log(.error, log).mapNever()
                        ]
                    }
                    
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .authorization(signedAuthorization),
                        forOriginalTransactionID: okResponse.originalTransactionID,
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
                        forOriginalTransactionID: okResponse.originalTransactionID,
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
                        forOriginalTransactionID: okResponse.originalTransactionID,
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
                
                effects.append(
                    environment.feedbackLogger.log(.error, "authorization request failed '\(failureEvent)'").mapNever()
                )
                
                if case .badRequest = failureEvent.error {
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .requestRejected(.badRequestError),
                        forOriginalTransactionID: purchase.originalTransactionID,
                        environment: environment
                    )
                    
                    effects.append(stateUpdateEffect.mapNever())
                    
                } else {
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .requestError(failureEvent.eraseToRepr()),
                        forOriginalTransactionID: purchase.originalTransactionID,
                        environment: environment
                    )
                    
                    effects.append(stateUpdateEffect.mapNever())
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

extension Dictionary where Key == OriginalTransactionID, Value == SubscriptionPurchaseAuthState {
    
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
        
        // updatedPurchases with latest expiry, hashed by OriginalTransactionID.
        let altUpdatedPurchases = Set(updatedPurchases.sortedByExpiry().reversed().map {
            HashableView($0, \.originalTransactionID)
        })

        let updatedPurchasesDict = [OriginalTransactionID: SubscriptionIAPPurchase](
            uniqueKeysWithValues: altUpdatedPurchases.map {
                ($0.value.originalTransactionID, $0.value)
            }
        )
        return updatedPurchasesDict.mapValues {
            SubscriptionPurchaseAuthState(
                purchase: $0,
                signedAuthorization: self[$0.originalTransactionID]?.signedAuthorization ?? .notRequested
            )
        }
    }
    
    func contains(originalTransactionID: OriginalTransactionID) -> Bool {
        self.contains { (key, _) -> Bool in
            key == originalTransactionID
        }
    }
    
}

extension SubscriptionPurchaseAuthState {
    
    /// `canRequestAuthorization` determines whether an authorization request could be sent to the purchase verifier
    /// server based on the current state of `signedAuthorization`, and device clock.
    func canRequestAuthorization(
        getCurrentTime: () -> Date,
        compareDates: (Date, Date, Calendar.Component) -> ComparisonResult
    ) -> Bool {
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
            let isExpired = self.purchase.isApproximatelyExpired(
                getCurrentTime: getCurrentTime,
                compareDates: compareDates
            )
            return !isExpired
        }
    }
    
}

/// State update functions.
extension SubscriptionAuthState {
    
    mutating func setAuthorizationState(
        newValue: SubscriptionPurchaseAuthState.AuthorizationState,
        forOriginalTransactionID originalTransactionID: OriginalTransactionID,
        environment: SubscriptionAuthStateReducerEnvironment
    ) -> Effect<Never> {
        guard var purchasesAuthState = self.purchasesAuthState else {
            fatalError()
        }
        
        guard var currentValue = purchasesAuthState.removeValue(forKey: originalTransactionID) else{
            fatalError("expected original transaction ID '\(originalTransactionID)'")
        }
        
        currentValue.signedAuthorization = newValue
        purchasesAuthState[originalTransactionID] = currentValue
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
    
    /// Returned effect emits stored data with type `[OriginalTransactionID, SubscriptionPurchaseAuthState]`.
    /// If there is no stored data, returns an empty dictionary.
    static func getValue(
        sharedDB: SharedDBContainer
    ) -> Effect<Result<StoredDataType, SystemErrorEvent>> {
        Effect { () -> Result<StoredDataType, SystemErrorEvent> in
            guard let data = sharedDB.getSubscriptionAuths() else {
                return .success([:])
            }
            do {
                let decoded = try JSONDecoder.makeRfc3339Decoder()
                    .decode(StoredDataType.self, from: data)
                return .success(decoded)
            } catch {
                return .failure(SystemErrorEvent(SystemError(error)))
            }
        }
    }
    
    /// Encodes `value` and stores the `Data` in `sharedDB`.
    static func setValue(
        sharedDB: SharedDBContainer, value: StoredDataType
    ) -> Effect<Result<(), SystemErrorEvent>> {
        Effect { () -> Result<(), SystemErrorEvent> in
            do {
                guard !value.isEmpty else {
                    sharedDB.setSubscriptionAuths(nil)
                    return .success(())
                }
                let data = try JSONEncoder.makeRfc3339Encoder().encode(value)
                sharedDB.setSubscriptionAuths(data)
                return .success(())
            } catch {
                return .failure(SystemErrorEvent(SystemError(error)))
            }
        }
    }
    
}
