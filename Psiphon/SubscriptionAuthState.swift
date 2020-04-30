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

/// Represents authorization state for subscription purchase.
struct SubscriptionPurchaseAuthState: Hashable, Codable {
    
    enum AuthorizationState: Hashable {
        
        enum RequestRejectedReason: String, Codable {
            /// Received 400-Bad Request error from the purhcase verifier server.
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
        case authorization(SignedAuthorization)
        
        /// Authorization rejected by the Psiphon servers.
        /// If the transaction has not expired, another authorization can be requested from the purchase verifier server.
        case rejectedByPsiphon(SignedAuthorization)
    }
    
    /// Subscription purchase contained in the app receipt.
    let purchase: SubscriptionIAPPurchase
    
    /// State of authorization for the `purchase`.
    var signedAuthorization: AuthorizationState

}

enum SubscriptionAuthStateAction {
    
    enum StoredDataUpdateType {
        case didUpdateRejectedSubscritionAuthIDs
        case didRefreshReceiptData(ReceiptReadReason)
    }
    
    case localDataUpdate(type: StoredDataUpdateType)
    
    case didLoadStoredPurchaseAuthState(
        loadResult: Result<SubscriptionAuthState.PurchaseAuthStateDict, SystemErrorEvent>,
        replayDataUpdate: StoredDataUpdateType?
    )
    
    case requestAuthorizationForPurchases
    
    case _localDataUpdateResult(
        transformer: (SubscriptionAuthState.PurchaseAuthStateDict) ->
            (SubscriptionAuthState.PurchaseAuthStateDict, [Effect<SubscriptionAuthStateAction>])
    )
    
    case _authorizationRequestResult(
        result: RetriableTunneledHttpRequest<SubscriptionValidationResponse>.RequestResult,
        forPurchase: SubscriptionIAPPurchase
    )
}

typealias SubscriptionAuthStateReducerEnvironment = (
    notifier: Notifier,
    sharedDB: PsiphonDataSharedDB,
    tunnelStatusWithIntentSignal: SignalProducer<VPNStatusWithIntent, Never>,
    clientMetaData: ClientMetaData,
    getCurrentTime: () -> Date,
    compareDates: (Date, Date, Calendar.Component) -> ComparisonResult
)

struct SubscriptionAuthState: Equatable {
    
    typealias PurchaseAuthStateDict = [OriginalTransactionID: SubscriptionPurchaseAuthState]
    
    /// `nil` represents that subscription auths have not been restored from previously stored value.
    /// This value is in  sync with stored value in  `PsiphonDataSharedDB`
    /// with key `subscription_authorizations_dict`.
    private(set) var purchasesAuthState: PurchaseAuthStateDict? = .none
    
    /// Set of transactions that either have a pending authorization request (either in-flight or pending tunnel connected).
    var transactionsPendingAuthRequest = Set<OriginalTransactionID>()
}

struct SubscriptionReducerState<T: TunnelProviderManager>: Equatable {
    var subscription: SubscriptionAuthState
    let receiptData: ReceiptData?
    let tunnelManagerRef: WeakRef<T>?
}

func subscriptionAuthStateReducer<T: TunnelProviderManager>(
    state: inout SubscriptionReducerState<T>, action: SubscriptionAuthStateAction,
    environment: SubscriptionAuthStateReducerEnvironment
) -> [Effect<SubscriptionAuthStateAction>] {
    switch action {
    
    case .localDataUpdate(type: let updateType):
        guard let receiptData = state.receiptData else {
            return [
                Effect(value:
                    .didLoadStoredPurchaseAuthState(
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
                        .didLoadStoredPurchaseAuthState(
                            loadResult: $0,
                            replayDataUpdate: updateType
                        )
                }
            ]
        }
        
        let receiptInAppPurchases = receiptData.subscriptionInAppPurchases
        
        return [
            StoredRejectedSubscriptionAuthIDs.getValue(sharedDB: environment.sharedDB)
                .map { rejectedAuthIDs -> SubscriptionAuthStateAction in
                    ._localDataUpdateResult { current in
                        
                        var effects = [Effect<SubscriptionAuthStateAction>]()
                        
                        // Merges subscription purchases present in the receipt,
                        // with `current` data for the given purchases.
                        var newValue = current.merge(withUpdatedPurchases: receiptInAppPurchases)
                        
                        // If the receipt is refreshed form the App Store,
                        // resets authorization state to `.notRequested`, for any
                        // purchase whose authorization requested result in 400-Bad request error.
                        if case .didRefreshReceiptData(let readReason) = updateType {
                            newValue = newValue.resetAuthorizationBadRequest(
                                forReceiptUpdateType: readReason
                            )
                        }
                        
                        // Updates authorization state for any purchase that had it's authroization
                        // rejected by Psiphon servers.
                        newValue = newValue.updateAuthorizationState(
                            givenRejectedAuthIDs: rejectedAuthIDs
                        )
                        
                        effects.append(
                            StoredRejectedSubscriptionAuthIDs.setContainerReadRejectedAuthIDs(
                                sharedDB: environment.sharedDB
                            ).fireAndForget()
                        )
                        
                        return (newValue, effects)
                    }
                }
        ]
        
    case let .didLoadStoredPurchaseAuthState(loadResult: loadResult, replayDataUpdate: updateType):
        switch loadResult {
        case .success(let loadedValue):
            var effects = [Effect<SubscriptionAuthStateAction>]()
            
            effects.append(
                state.subscription.setPurchasesAuthState(
                    newValue: loadedValue,
                    environment:  environment
                ).mapNever()
            )
            
            // Replays `localDataUpdate(type:)` action if not nil.
            if let updateType = updateType {
                effects.append(Effect(value: .localDataUpdate(type: updateType)))
            }
            
            return effects
            
        case .failure(let errorEvent):
            // Reading from PsiphonDataSharedDB failed.
            // Resets value of stored subscription purchase auth state.
            
            let stateUpdateEffect = state.subscription.setPurchasesAuthState(
                newValue: [:],
                environment: environment
            )
            
            return [
                stateUpdateEffect.then(
                    Effect(value: .localDataUpdate(type: .didRefreshReceiptData(.localRefresh)))
                ),
                
                feedbackLog(.error, "failed reading stored subscription auth state '\(errorEvent)'")
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
                Effect(value: .requestAuthorizationForPurchases)
            ]
        }
        
        let stateUpdateEffect = state.subscription.setPurchasesAuthState(
            newValue: newValue,
            environment: environment
        )
        
        return effects + [
            stateUpdateEffect.mapNever(),
            Effect(value: .requestAuthorizationForPurchases)
        ]
        
    case .requestAuthorizationForPurchases:
        
        guard let tunnelManagerRef = state.tunnelManagerRef else {
            return []
        }
        
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
        let authRequest = RetriableTunneledHttpRequest(
            request: PurchaseVerifierServerEndpoints.subscription(
                requestBody: SubscriptionValidationRequest(
                    originalTransactionID: purchaseWithLatestExpiry.purchase.originalTransactionID,
                    receipt: receiptData
                ),
                clientMetaData: environment.clientMetaData
            )
        )
        
        return [
            authRequest.makeRequestSignal(
                tunnelStatusWithIntentSignal: environment.tunnelStatusWithIntentSignal,
                tunnelManagerRef: tunnelManagerRef
            ).map {
                ._authorizationRequestResult(
                    result: $0,
                    forPurchase: purchaseWithLatestExpiry.purchase
                )
            },
            feedbackLog(.info, """
                initiated auth request for original transaction ID \
                \(purchaseWithLatestExpiry.purchase.originalTransactionID)
                """).mapNever()
        ]
        
        
    case let ._authorizationRequestResult(result: requestResult, forPurchase: purchase):
        guard
            state.subscription.transactionsPendingAuthRequest
                .contains(purchase.originalTransactionID)
            else {
                fatalError()
        }
        
        guard let purchasesAuthState = state.subscription.purchasesAuthState else {
            fatalError()
        }
        
        guard purchasesAuthState.contains(originalTransactionID: purchase.originalTransactionID)
            else {
            fatalError("""
                expected 'state.subscription.purchaseAuthStates' to contain \
                transctaion ID '\(purchase.transactionID)'
                """)
        }
        
        switch requestResult {
        case .willRetry(when: let retryCondition):
            switch retryCondition {
            case .tunnelConnected:
                // This event is too frequent to log individually.
                return []
            case .afterTimeInterval:
                return [ feedbackLog(.error, retryCondition).mapNever() ]
            }
            
        case .failed(let errorEvent):
            // Authorization request finished in failure.
            
            // Authorization request for this purchase is no longer pending.
            state.subscription.transactionsPendingAuthRequest.remove(purchase.originalTransactionID)
            
            let errorRepr = errorEvent.map { ErrorRepr(repr: String(describing: $0)) }
            
            let stateUpdateEffect = state.subscription.setAuthorizationState(
                newValue: .requestError(errorRepr),
                forOriginalTransactionID: purchase.originalTransactionID,
                environment: environment
            )
            
            return [
                stateUpdateEffect.mapNever(),
                feedbackLog(.error, "authorization request failed '\(errorEvent)'").mapNever()
            ]
            
        case .completed(let subscriptionValidationResult):
            // Authorization request completed with a response from puchase verifier server.
            
            // Authorization request for this purchase is no longer pending.
            state.subscription.transactionsPendingAuthRequest.remove(purchase.originalTransactionID)
            
            switch subscriptionValidationResult {
                
            case .success(let okResponse):
                // 200-OK response from the purchase verifier server.
                guard okResponse.originalTransactionID == purchase.originalTransactionID else {
                    fatalError("""
                        sever transaction ID '\(okResponse.originalTransactionID)' did not match \
                        expected transaction ID '\(purchase.originalTransactionID)'
                        """)
                }
                
                switch okResponse.errorStatus {
                case .noError:
                    guard let signedAuthorization = okResponse.signedAuthorization else {
                        fatalError("expected 'signed_authorization' in response '\(okResponse)'")
                    }
                    
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .authorization(signedAuthorization),
                        forOriginalTransactionID: okResponse.originalTransactionID,
                        environment: environment
                    )
                    
                    return [
                        stateUpdateEffect.mapNever(),
                        feedbackLog(.info, """
                            authorization request completed with auth id \
                            '\(signedAuthorization.authorization.id)' expiring on \
                            '\(signedAuthorization.authorization.expires)'
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
                        feedbackLog(.error, """
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
                        feedbackLog(.error, """
                            authorization request completed with error \
                            '\(okResponse.errorDescription)'
                            """).mapNever()
                    ]
                }
                
            case .failure(let failureEvent):
                // Non-200 OK response from the purchase verifier server.
                var effects = [Effect<SubscriptionAuthStateAction>]()
                
                effects.append(
                    feedbackLog(.error, "authorization request failed '\(failureEvent)'").mapNever()
                )
                
                if case .badRequest = failureEvent.error {
                    let stateUpdateEffect = state.subscription.setAuthorizationState(
                        newValue: .requestRejected(.badRequestError),
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
            
            guard rejectedAuthIDs.contains(signedAuth.authorization.id) else {
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
    /// Note: Tranaction IDs are regenerated after subscription is restored.
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
    
    /// `canRequestAuthorization` determintes whether an authorization request could be sent to the purchase verifier
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
                    environment.notifier.post(NotifierUpdatedSubscriptionAuths)
                }
            )
    }
    
}

// MARK: Effects

fileprivate enum StoredRejectedSubscriptionAuthIDs {
    
    static func getValue(sharedDB: PsiphonDataSharedDB) -> Effect<Set<AuthorizationID>> {
        Effect { () -> Set<AuthorizationID> in
            return Set(sharedDB.getRejectedSubscriptionAuthorizationIDs())
        }
    }
    
    static func setContainerReadRejectedAuthIDs(sharedDB: PsiphonDataSharedDB) -> Effect<()> {
        Effect { () -> Void in
            sharedDB.updateContainerRejectedSubscriptionAuthIdReadSequenceNumber()
        }
    }
    
}

fileprivate enum StoredSubscriptionPurchasesAuthState {
    
    typealias StoredDataType = SubscriptionAuthState.PurchaseAuthStateDict
    
    /// Returned effect emits stored data with type `[OriginalTransactionID, SubscriptionPurchaseAuthState]`.
    /// If there is no stored data, returns an empty dictionary.
    static func getValue(
        sharedDB: PsiphonDataSharedDB
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
                return .failure(SystemErrorEvent(error as SystemError))
            }
        }
    }
    
    /// Encodes `value` and stores the `Data` in `sharedDB`.
    static func setValue(
        sharedDB: PsiphonDataSharedDB, value: StoredDataType
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
                return .failure(SystemErrorEvent(error as SystemError))
            }
        }
    }
    
}
