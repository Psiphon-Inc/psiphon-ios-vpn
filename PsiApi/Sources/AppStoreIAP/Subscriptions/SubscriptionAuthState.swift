/*
 * Copyright (c) 2021, Psiphon Inc.
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
import StoreKit


// TODO: Handle subscription cancellations
// https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode

/// Represents state of requesting an authorization for a subscription transaction.
public struct SubscriptionTransactionAuthRequestState: Hashable {
    
    /// Represents all possible failure cases of retrieving an authorization for a subscription transaction.
    public enum AuthorizationRequestFailure: HashableError {
        
        /// Represents set of reasons for which an authorization request was rejected
        /// by the purchase verifier servers. Retrying is unlikely to change the outcome.
        public enum RequestRejectedReason: Hashable {
            /// Received 400 Bad Request error from the purchase verifier servers.
            /// The request can be retried again only after a app receipt refresh.
            case badRequestError
            /// Subscription expiry date has passed.
            /// Request should not be retried.
            case transactionExpired
            /// Purchase has been cancelled by Apple customer support.
            /// Request should not be retried.
            case transactionCancelled
        }
        
        /// Authorization request failed. Request can be retried again later.
        case requestError(ErrorEvent<ErrorRepr>)
        
        /// Authorization request rejected by the purchase verifier server.
        /// Authorization request should **not** be retried for this transaction anymore,
        /// unless the receipt file is refreshed by App Store depending on the `RequestRejectedReason`.
        case requestRejected(RequestRejectedReason)
        
    }
    
    /// Subscirption transaction contained in the local app receipt.
    public let purchase: SubscriptionIAPPurchase
    
    /// Authorization request result.
    /// `nil` implies a request has not been made.
    /// `.pending` value implies that the authorization request is either in-flight or pending tunnel connected event.
    public var authorization: Optional<Pending<Result<SignedData<SignedAuthorization>,
                                             AuthorizationRequestFailure>>>
    
}

extension SubscriptionTransactionAuthRequestState {
    
    /// Returns `true` if a request can be made to the purchase verifier server,
    /// based on the current authorization state.
    /// - Note: In the case of retries, `true` only means the request can be retried after some
    ///         reasonable delay, and probably not immediately.
    var canRequestAuthorization: Bool {
        switch authorization {
        case .none:
            return true
        case .pending:
            return false
        case .completed(let result):
            switch result {
            case .success(_):
                return false
            case .failure(.requestError(_)):
                // Authorization request failed probably due to a network error.
                // Request can be retried again later.
                return true
            case .failure(.requestRejected(_)):
                // Request should probably not be retried, at least
                // until the local app receipt is refreshed.
                return false
            }
        }
    }
    
}

public enum SubscriptionAuthStateAction {
    
    /// Represents the event where the local app receipt data is read and
    /// it's in-memory representation in the app is updated.
    /// Consecutive firing of this event does not need to imply the receipt data
    /// has necessarily changed, however it will prevent redundant work.
    case appReceiptDataUpdated(ReceiptData?, ReceiptReadReason)
    
    /// Action to update transactions' authorization state, given updated
    /// receipt data (along with the reason receipt was read),
    /// and current persisted subscription authorizations.
    case _updateTransactionsAuthState(ReceiptData,
                                      ReceiptReadReason,
                                      Result<Set<SharedAuthorizationModel>, CoreDataError>)
    
    /// Represents result of syncing authorizations with Core Data.
    /// Boolean success result represents whether any changes have been made to the persistent store.
    case _coreDataSyncResult(Result<Bool, CoreDataError>)
    
    /// Result of an authorization HTTP request for a given subscription transaction.
    case _authorizationRequestResult(
        result: RetriableTunneledHttpRequest<SubscriptionValidationResponse>.RequestResult,
        forTransaction: SubscriptionIAPPurchase
    )
    
}


public struct SubscriptionAuthState: Equatable {
    
    public typealias TransactionsAuthState =
    [WebOrderLineItemID: SubscriptionTransactionAuthRequestState]
    
    /// Represents authorization request for all subscription transactions present in the local app receipt.
    ///
    /// Value is `nil` if not initialized yet. Initialization here means that local receipt, and persisted
    /// authorization in `SharedCoreData` were both loaded and merged to produce a value here.
    public var transactionsAuthState: TransactionsAuthState? = .none
    
    public init() {}
    
}

extension SubscriptionAuthState {
    
    /// True if there are any transactions with pending authorization request.
    public var anyPendingAuthRequests: Bool {
        guard let transactionsAuthState = self.transactionsAuthState else {
            return false
        }
        let pendingAuths = transactionsAuthState.values.filter {
            switch $0.authorization {
            case .none, .pending:
                return true
            case .completed(_):
                return false
            }
        }
        return !pendingAuths.isEmpty
    }
    
    /// Set of SharedAuthorizationModel values for all subscriptions in `transactionsAuthState`
    /// that have an authorization.
    /// - Note: `psiphondRejected` is set to `false`.
    func getSharedAuthorizationModels() -> Set<SharedAuthorizationModel> {
        guard let transactionsAuthState = self.transactionsAuthState else {
            return Set()
        }
        return Set(transactionsAuthState.compactMap { (key, value) in
            guard case .completed(.success(let signedAuth)) = value.authorization else {
                return nil
            }
            return SharedAuthorizationModel(
                authorization: signedAuth,
                webOrderLineItemID: key,
                psiphondRejected: false
            )
        })
    }
        
}

public let subscriptionAuthStateReducer = Reducer<SubscriptionAuthState,
                                                  SubscriptionAuthStateAction,
                                                  SubscriptionAuthStateReducerEnvironment>
{ state, action, environment in
    
    switch action {
        
    case let .appReceiptDataUpdated(receiptData, receiptReadReason):
        
        // state.transactionsAuthState should be empty if there is no local app receipt.
        guard let receiptData = receiptData else {
            
            state.transactionsAuthState = [:]
            
            return [
                // Syncs with Core Data.
                environment.sharedAuthCoreData
                    .syncAuthorizationsWithSharedCoreData(
                        Authorization.AccessType.subscriptionTypes,
                        Set(),
                        environment.mainDispatcher)
                    .map { ._coreDataSyncResult($0) }
            ]
        }
        
        // Emits `_updateTransactionsAuthState` with current app receipt subscription
        // transactions, and persisted authorization data.
        return [
            environment.sharedAuthCoreData
                .getPersistedAuthorizations(psiphondRejected: nil,
                                            Authorization.AccessType.subscriptionTypes,
                                            environment.mainDispatcher)
                .map { ._updateTransactionsAuthState(receiptData, receiptReadReason, $0) }
        ]
    
    case let ._updateTransactionsAuthState(receiptData,
                                           receiptReadReason,
                                           persistedAuthResult):
        
        // Updates subscription transaction's authorization state,
        // given the receiptData, and persisted subscription authorizations.
        
        switch persistedAuthResult {
            
        case .success(let persistedAuthorizations):
            
            let nonExpiredPurchases = receiptData.subscriptionInAppPurchases.filter { purchase in
                !purchase.isApproximatelyExpired(environment.dateCompare)
            }
            
            // Checks if there are any active (non-expired) subscription transactions.
            guard nonExpiredPurchases.count > 0 else {
                
                state.transactionsAuthState = [:]
                
                return [
                    // Syncs updated authorizations with Core Data.
                    environment.sharedAuthCoreData
                        .syncAuthorizationsWithSharedCoreData(
                            Authorization.AccessType.subscriptionTypes,
                            Set(),
                            environment.mainDispatcher)
                        .map { ._coreDataSyncResult($0) }
                ]
                
            }
            
            // Constructs new subscriptions auth state given it's current state,
            // transactions found in the local receipt and authorizations already persisted.
            state.transactionsAuthState = makeTransactionsAuthState(
                currentAuthRequestStates: state.transactionsAuthState,
                nonExpiredPurchases: nonExpiredPurchases,
                receiptReadReason: receiptReadReason,
                persistedAuthorizations: persistedAuthorizations)
            
            var effects = [Effect<SubscriptionAuthStateAction>]()
            
            // We only ever expect a single (non-expired) subscription purchase which doesn't have
            // an authorization at a time. So the first subscription transaction without
            // authorization is selected. Even if this is not always true, it would not cause
            // any issues.
            let txWithoutAuth = (state.transactionsAuthState ?? [:])
                .values
                .filter { $0.canRequestAuthorization }
                .first
            
            if let txWithoutAuth = txWithoutAuth {
                
                // Updates transaction's authorization state to pending.
                state.transactionsAuthState![txWithoutAuth.purchase.webOrderLineItemID] =
                SubscriptionTransactionAuthRequestState(
                    purchase: txWithoutAuth.purchase,
                    authorization: .pending
                )
                
                // Authorization request effect to purchase verifier server for `txWithoutAuth`.
                effects += makeAuthorizationRequest(
                    purchase: txWithoutAuth.purchase,
                    receiptData: receiptData,
                    clientMetaData: environment.clientMetaData,
                    retryCount: environment.httpRequestRetryCount,
                    retryInterval: environment.httpRequestRetryInterval,
                    getCurrentTime: environment.dateCompare.getCurrentTime,
                    tunnelStatusSignal: environment.tunnelStatusSignal,
                    tunnelConnectionRefSignal: environment.tunnelConnectionRefSignal,
                    httpClient: environment.httpClient
                ).map {
                    ._authorizationRequestResult(result: $0,
                                                 forTransaction: txWithoutAuth.purchase)
                }
                
                effects += environment.feedbackLogger.log(.info, """
                    Initiated auth request for subscription purchase \
                    WebOrderLineItemID(\(txWithoutAuth.purchase.webOrderLineItemID))
                    """).mapNever()
                
            }
            
            // Syncs updated authorizations with Core Data.
            effects += environment.sharedAuthCoreData
                .syncAuthorizationsWithSharedCoreData(
                    Authorization.AccessType.subscriptionTypes,
                    state.getSharedAuthorizationModels(),
                    environment.mainDispatcher)
                .map { ._coreDataSyncResult($0) }
            
            return effects
            
        case .failure(let error):
            // Failed to read subscription authorization data from Core Data.
            // Currently this failure event is only logged.
            return [
                environment.feedbackLogger.log(
                    .error, "Failed to get auth data from Core Data: \(error)"
                ).mapNever()
            ]
        }
        
    case ._coreDataSyncResult(let syncResult):
        
        // Notifies the Network Extension of any changes to persisted authorization in Core Data.
        // Errors with Core Data are only logged, and no further action is taken at this point.
        
        switch syncResult {
            
        case .success(let changed):
            
            var effects = [Effect<SubscriptionAuthStateAction>]()
            
            if changed {
                // Notifies Network Extension if any changes have been made to the peristent store.
                effects += .fireAndForget {
                    environment.notifier.post(environment.notifierUpdatedAuthorizationsMessage)
                }
            }
            
            effects += environment.feedbackLogger.log(
                .info, "Synced subscription authorizations with Core Data")
                .mapNever()
            
            return effects
            
        case .failure(let error):
            
            return [
                environment.feedbackLogger.log(
                    .error, "Failed to sync subscription authorization with Core Data: \(error)"
                ).mapNever()
            ]
        }
        
        
    case let ._authorizationRequestResult(result: requestResult, forTransaction: transaction):
        
        // Should never happen, however state.transactionsAuthState should have been initialized.
        guard let transactionsAuthState = state.transactionsAuthState else {
            environment.feedbackLogger.fatalError("transactionsAuthState is not initialized")
            return []
        }
        
        // If the transaction that this authorization request response belongs to
        // no longer exists, we will ignore the result.
        guard
            let transactionAuthState = transactionsAuthState[transaction.webOrderLineItemID]
        else {
            environment.feedbackLogger.fatalError("Matching purchase not found")
            return [
                environment.feedbackLogger.log(.warn,"""
                    Purchase with WebOrderLineItemID(\(transaction.webOrderLineItemID) not found
                    """).mapNever()
            ]
        }
        
        switch requestResult {
            
        case .willRetry(let retryCondition):
            switch retryCondition {
            case .whenResolved(tunnelError: .nilTunnelProviderManager):
                // VPN config is not installed, request will be retired once VPN config
                // is installed and loaded successfully.
                // TODO! test this condition when VPN config is not installed.
                return [ environment.feedbackLogger.log(.error, retryCondition).mapNever() ]
                
            case .whenResolved(tunnelError: .tunnelNotConnected):
                // This event is too frequent to log.
                return []
                
            case .afterTimeInterval:
                return [ environment.feedbackLogger.log(.error, retryCondition).mapNever() ]
            }
            
        case .completed(let subscriptionValidationResult):
            // Authorization request finished. Request may have been already retried
            // automatically if it has failed.
            
            switch subscriptionValidationResult {
                
            case .success(let okResponse):
                // 200 OK response from the purchase-verifier server.
                // Note 200 OK response does not imply an authorization has been retrieved,
                // error_status field of the JSON response should be checked first.
                
                // Sanity-check.
                guard okResponse.webOrderLineItemID == transaction.webOrderLineItemID else {
                    
                    let log: LogMessage =
                        """
                        Sever WebOrderLineItemID '\(okResponse.webOrderLineItemID)' did not match \
                        expected WebOrderLineItemID '\(transaction.webOrderLineItemID)'
                        """
                    let errorEvent = ErrorEvent(ErrorRepr(repr: String(describing:log)),
                                                date: okResponse.requestDate)
                    
                    state.transactionsAuthState![transaction.webOrderLineItemID] =
                    SubscriptionTransactionAuthRequestState(
                        purchase: transaction,
                        authorization: .completed(.failure(.requestError(errorEvent)))
                    )

                    return [
                        environment.feedbackLogger.log(.error, log).mapNever()
                    ]
                    
                }
                
                switch okResponse.errorStatus {
                
                case .noError:
                    // Gets signed_authorization from the response.
                    // It is a programming error if this field does not exist.
                    guard let signedAuthorization = okResponse.signedAuthorization else {
                        
                        let log: LogMessage = "Expected 'signed_authorization' in response '\(okResponse)'"
                        let errorEvent = ErrorEvent(ErrorRepr(repr: String(describing:log)),
                                                    date: okResponse.requestDate)
                        
                        state.transactionsAuthState![transaction.webOrderLineItemID] =
                        SubscriptionTransactionAuthRequestState(
                            purchase: transaction,
                            authorization: .completed(.failure(.requestError(errorEvent)))
                        )
                        
                        return [
                            environment.feedbackLogger.log(.error, log).mapNever()
                        ]
                        
                    }
                    
                    // Updates transactionsAuthState with the new authorization.
                    state.transactionsAuthState![transaction.webOrderLineItemID] =
                    SubscriptionTransactionAuthRequestState(
                        purchase: transaction,
                        authorization: .completed(.success(signedAuthorization))
                    )
                    
                    return [
                        // Syncs updated authorizations with Core Data.
                        environment.sharedAuthCoreData
                            .syncAuthorizationsWithSharedCoreData(
                                Authorization.AccessType.subscriptionTypes,
                                state.getSharedAuthorizationModels(),
                                environment.mainDispatcher)
                            .map { ._coreDataSyncResult($0) },
                        
                        environment.feedbackLogger.log(.info, """
                        Authorization request completed with auth id \
                        '\(signedAuthorization.decoded.authorization.id)' expiring on \
                        '\(signedAuthorization.decoded.authorization.expires)'
                        """).mapNever()
                    ]
                    
                case .transactionExpired:
                    // Updates transactionsAuthState with failed state.
                    // Since authorizations have not changed (none removed or added),
                    // there is no need to sync with Core Data.
                    state.transactionsAuthState![transaction.webOrderLineItemID] =
                    SubscriptionTransactionAuthRequestState(
                        purchase: transaction,
                        authorization: .completed(.failure(.requestRejected(.transactionExpired)))
                    )
                    
                    return [
                        environment.feedbackLogger.log(.info, """
                        Authorization request completed with error '\(okResponse.errorDescription)'
                        """).mapNever()
                    ]
                    
                case .transactionCancelled:
                    // Updates transactionsAuthState with failed state.
                    // Since authorizations have not changed (none removed or added),
                    // there is no need to sync with Core Data.
                    state.transactionsAuthState![transaction.webOrderLineItemID] =
                    SubscriptionTransactionAuthRequestState(
                        purchase: transaction,
                        authorization: .completed(.failure(.requestRejected(.transactionCancelled)))
                    )
                    
                    return [
                        environment.feedbackLogger.log(.info, """
                        Authorization request completed with error '\(okResponse.errorDescription)'
                        """).mapNever()
                    ]
                    
                }
                
            case .failure(let failureEvent):
                // Authorization request failed.
                
                switch failureEvent.error {
                case .badRequest:
                    
                    // Request rejected by the server.
                    // Request should not be retried until at least the local
                    // receipt is refreshed.
                    // User subscription status can be shown as not subscribed,
                    // or the user should be given a chance to be able to refresh
                    // their local app receipt.
                    
                    // Since authorizations have not changed (none removed or added),
                    // there is no need to sync with Core Data.
                    state.transactionsAuthState![transaction.webOrderLineItemID] =
                    SubscriptionTransactionAuthRequestState(
                        purchase: transaction,
                        authorization: .completed(.failure(.requestRejected(.badRequestError)))
                    )
                    
                case .serverError(_),
                        .unknownStatusCode(_),
                        .failedRequest(_),
                        .responseBodyParseError(_):
                    
                    // Request failed due to either a network failure, a server misconfiguration
                    // or an unknown error.
                    // All of these errors are treated the same, and the request can be retried
                    // later. Request may have been retried automatically.
                    
                    // Since authorizations have not changed (none removed or added),
                    // there is no need to sync with Core Data.
                    state.transactionsAuthState![transaction.webOrderLineItemID] =
                    SubscriptionTransactionAuthRequestState(
                        purchase: transaction,
                        authorization: .completed(.failure(.requestError(failureEvent.eraseToRepr())))
                    )
                    
                }
                
                return [
                    environment.feedbackLogger.log(.error, """
                    Authorization request failed for \
                    WebOrderLineItemId(\(transaction.webOrderLineItemID)): \
                    \(failureEvent)
                    """).mapNever()
                ]
                
            }
            
            
        }
        
    }
    
}

/// Constructs a new `TransactionsAuthState` value by combining current values,
/// with current subscription purchases in the local app receipt, and authorizations
/// already persisted.
/// - Parameter currentAuthRequestState: Current transactions auth request  state.
/// - Parameter nonExpiredPurchases: Subscription transactions in the local app receipt
///                                  that have not expired
/// - Parameter receiptReadReason: Whether the local app receipt was refreshed or not.
/// - Parameter persistedAuthorizations: Subscription authorizations that have been persisted.
func makeTransactionsAuthState(
    currentAuthRequestStates: SubscriptionAuthState.TransactionsAuthState?,
    nonExpiredPurchases: Set<SubscriptionIAPPurchase>,
    receiptReadReason: ReceiptReadReason,
    persistedAuthorizations: Set<SharedAuthorizationModel>
) -> SubscriptionAuthState.TransactionsAuthState {
    
    // Combines non-expired subscription transactions in the local app receipt,
    // with authorizations already persisted.
    let newTransactionsAuthState: [(WebOrderLineItemID, SubscriptionTransactionAuthRequestState)] =
    nonExpiredPurchases.map { subscriptionPurchase in
        
        let key = subscriptionPurchase.webOrderLineItemID
        
        let persistedMatch = persistedAuthorizations.filter {
            $0.webOrderLineItemID == key
        }.first
        
        let authRequestState:  SubscriptionTransactionAuthRequestState
        
        if let persistedMatch = persistedMatch {
            
            // A persisted authorization has been found.
            authRequestState = SubscriptionTransactionAuthRequestState(
                purchase: subscriptionPurchase,
                authorization: .completed(.success(persistedMatch.authorization))
            )
            
        } else {
            
            // No authorization has been persisted for this subscription purchase.
            // If there is already an "autorization request state" value for the
            // given WebOrderLineItemID of `subscriptionPurchase`, it is used
            // (current state is kept and not reset unless the app receipt is refreshed.)
            // Otherwise, the "authorization request state" is set to `nil`.
            
            if let value = currentAuthRequestStates?[key] {
                
                if case .remoteRefresh = receiptReadReason,
                   case .completed(.failure(.requestRejected(.badRequestError))) = value.authorization {
                    
                       // Last request resulted in bad request error.
                       // Since the receipt is refreshed,it's authorization
                       // state is reset so that it can be retired again.
                       authRequestState = SubscriptionTransactionAuthRequestState(
                        purchase: subscriptionPurchase,
                        authorization: .none
                       )
                       
                   } else {
                       authRequestState = value
                   }
                
            } else {
                authRequestState = SubscriptionTransactionAuthRequestState(
                    purchase: subscriptionPurchase,
                    authorization: .none
                )
            }
            
        }
        
        return (subscriptionPurchase.webOrderLineItemID, authRequestState)
        
    }
    
    // Maps list of (key, value) tuples to a dictionary.
    return Dictionary(uniqueKeysWithValues: newTransactionsAuthState)
    
}

/// Makes a authorization request effect for the given subscription `purchase`.
func makeAuthorizationRequest(
    purchase: SubscriptionIAPPurchase,
    receiptData: ReceiptData,
    clientMetaData: () -> ClientMetaData,
    retryCount: Int,
    retryInterval: DispatchTimeInterval,
    getCurrentTime: @escaping () -> Date,
    tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
    tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
    httpClient: HTTPClient
) -> Effect<RetriableTunneledHttpRequest<SubscriptionValidationResponse>.RequestResult> {
    
    let purchaseVerifierReq = PurchaseVerifierServer.subscription(
        requestBody: SubscriptionValidationRequest(
            originalTransactionID: purchase.originalTransactionID,
            webOrderLineItemID: purchase.webOrderLineItemID,
            productID: purchase.productID,
            receipt: receiptData
        ),
        clientMetaData: clientMetaData()
    )
    
    let httpReq = RetriableTunneledHttpRequest(
        request: purchaseVerifierReq.request,
        retryCount: retryCount,
        retryInterval: retryInterval
    )
    
    return httpReq(
        getCurrentTime: getCurrentTime,
        tunnelStatusSignal: tunnelStatusSignal,
        tunnelConnectionRefSignal: tunnelConnectionRefSignal,
        httpClient: httpClient
    )
    
}
