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
import AppStoreIAP
import PsiApi
import PsiCashClient

struct PsiCashReducerState: Equatable {
    var psiCashBalance: PsiCashBalance
    var psiCash: PsiCashState
    let subscription: SubscriptionState
    let tunnelConnection: TunnelConnection?
}

struct PsiCashEnvironment {
    let platform: Platform
    let feedbackLogger: FeedbackLogger
    let psiCashFileStoreRoot: String?
    let psiCashEffects: PsiCashEffectsProtocol
    let sharedAuthCoreData: SharedAuthCoreData
    let psiCashPersistedValues: PsiCashPersistedValues
    let notifier: PsiApi.Notifier
    let notifierUpdatedAuthorizationsMessage: String
    let vpnActionStore: (VPNPublicAction) -> Effect<Never>
    let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    // TODO: Remove this dependency from reducer's environment. UI-related effects
    // unnecessarily complicate reducers.
    let objcBridgeDelegate: ObjCBridgeDelegate?
    let metadata: () -> ClientMetaData
    let getCurrentTime: () -> Date
    let psiCashLegacyDataStore: UserDefaults
    let userConfigs: UserDefaultsConfig
    let mainDispatcher: MainDispatcher
    let clearWebViewDataStore: () -> Effect<Never>
}

let psiCashReducer = Reducer<PsiCashReducerState, PsiCashAction, PsiCashEnvironment> {
    state, action, environment in
    
    switch action {
    
    case .initialize:
        
        guard state.psiCash.libData == nil else {
            environment.feedbackLogger.fatalError("PsiCash already initialized")
            return []
        }
        
        return [
            environment.psiCashEffects.initialize(
                fileStoreRoot: environment.psiCashFileStoreRoot,
                psiCashLegacyDataStore: environment.psiCashLegacyDataStore,
                tunnelConnectionRefSignal: environment.tunnelConnectionRefSignal
            ).map(PsiCashAction._initialized)
        ]
    
    case ._initialized(let result):
        
        switch result {
        case let .success(libInitSuccess):
            state.psiCash.libData = .success(libInitSuccess.libData)
            state.psiCashBalance = .fromStoredExpectedReward(
                libData: libInitSuccess.libData, persisted: environment.psiCashPersistedValues)
            
            var effects = [Effect<PsiCashAction>]()
            
            let psiCashStateCopy = state.psiCash
            
            // Force-removes purchases in the PsiCash library that have their
            // authorization rejected by Psiphon servers.
            effects += environment.sharedAuthCoreData.getPersistedAuthorizations(
                psiphondRejected: true,
                Authorization.AccessType.speedBoostTypes,
                environment.mainDispatcher
            ).flatMap(.latest) { rejectsAuthsResult in
                
                let rejectedAuthIDs = rejectsAuthsResult.successToOptional()?
                    .map(\.authorization.decoded.authorization.id)
                
                // List of Transaction ID of PsiCash purchases to remove.
                let transactionsToRemove = psiCashStateCopy
                    .getPurchases(forAuthorizaitonIDs: rejectedAuthIDs ?? [])
                    .map(\.transaction.transactionId)
                
                return environment.psiCashEffects
                    .removePurchases(withTransactionIDs: transactionsToRemove)
                
            }.map { ._forceRemovedPurchases($0) }

            if libInitSuccess.requiresStateRefresh {

                state.psiCashBalance.balanceOutOfDate(reason: .psiCashDataStoreMigration)

                effects += Effect(value: .refreshPsiCashState())
            }
            
            // Sets locale after initialization.
            effects += Effect(value: .setLocale(environment.userConfigs.localeForAppLanguage))

            return effects
            
        case let .failure(error):
            
            state.psiCash.libData = .failure(error)
            
            return [
                environment.feedbackLogger.log(
                    .error, report: true, "failed to initialize PsiCash: \(error)")
                    .mapNever()
            ]
        }
    
    case .setLocale(let locale):
        
        // PsiCash Library must be initialized before setting locale.
        guard case .success(_) = state.psiCash.libData else {
            return [
                environment.feedbackLogger.log(.error, "lib not loaded")
                    .mapNever()
            ]
        }
        
        return [
            environment.psiCashEffects.setLocale(locale)
                .mapNever(),
            
            Effect(value: .refreshPsiCashState())
        ]
        
    case .purchaseDeferredProducts:
        
        // Checks if there is a deferred purchase.
        guard case let .deferred(purchasableType) = state.psiCash.purchase else {
            return []
        }

        // Sanity-check.
        guard
            case .success(_) = state.psiCash.libData,
            let tunnelConnection = state.tunnelConnection
        else {
            return []
        }
        
        return [
            Effect(value: .buyPsiCashProduct(purchasableType))
        ]
        
        
    case .buyPsiCashProduct(let purchasableType):
        
        // Only one PsiCash product purchase is made a time.
        // No-op if there is a pending purchase.
        // Note: Last deferred purchase will be replaced (if any).
        guard
            case .success(let libData) = state.psiCash.libData,
            let tunnelConnection = state.tunnelConnection,
            case .notSubscribed = state.subscription.status,
            !state.psiCash.purchase.pending
        else {
            return []
        }
        
        // Checks if there is sufficient funds (even if balance is not up-to-date).
        guard libData.balance >= purchasableType.expectedPrice else {
            
            // Creates insufficient error event of the same type as the actual server response.
            let errorEvent = NewExpiringPurchaseResult.ErrorType.init(
                .requestError(.errorStatus(.insufficientBalance)),
                date: environment.getCurrentTime()
            )
            
            state.psiCash.purchase = .error(errorEvent)
            
            return [
                environment.feedbackLogger.log(.info, """
                    insufficient balance
                    \(purchasableType.expectedPrice.inPsi) > \(libData.balance.inPsi)
                    """).mapNever()
            ]
            
        }
        
        // Purchase should be deferred if the tunnel is not connected.
        let deferred = tunnelConnection.tunneled != .connected
        
        if deferred {
            
            // Purchase is deferred until tunnel is connected.
            state.psiCash.purchase = .deferred(purchasableType)
            return [
                environment.vpnActionStore(.tunnelStateIntent(
                    intent: .start(transition: .none), reason: .userInitiated
                )).mapNever()
            ]
            
        } else {
            
            state.psiCash.purchase = .pending(purchasableType)
            
            // Purchase immediately.
            return [
                environment.psiCashEffects
                    .purchaseProduct(purchasable: purchasableType,
                                     tunnelConnection: tunnelConnection,
                                     clientMetaData: environment.metadata())
                    .map {
                        ._psiCashProductPurchaseResult(
                            purchasable: purchasableType,
                            result: $0
                        )
                    }
            ]
        }
        
        
    case let ._psiCashProductPurchaseResult(purchasableType, purchaseResult):
        
        guard case .pending(_) = state.psiCash.purchase else {
            environment.feedbackLogger.fatalError("""
                Expected '.pending' state:'\(String(describing: state.psiCash.purchase))'
                """)
            return []
        }
        
        guard case .speedBoost(_) = purchasableType else {
            environment.feedbackLogger.fatalError("""
                Only Speed Boost purchases are supported: '\(purchasableType)'
                """)
            return []
        }

        state.psiCash.libData = .success(purchaseResult.refreshedLibData)
        state.psiCashBalance = .refreshed(refreshedData: purchaseResult.refreshedLibData,
                                          persisted: environment.psiCashPersistedValues)

        switch purchaseResult.result {
        case let .success(newExpiringPurchaseResponse):
            
            switch newExpiringPurchaseResponse.purchasedType {
            
            case let .success(purchasedType):
                
                switch purchasedType {
                    
                case .speedBoost(let purchasedProduct):
                    
                    state.psiCash.purchase = .none
                    
                    return [
                        
                        // Persists Speed Boost authorization with Core Data.
                        environment.sharedAuthCoreData
                            .syncAuthorizationsWithSharedCoreData(
                                Authorization.AccessType.speedBoostTypes,
                                state.psiCash.getSharedAuthorizationModels(),
                                environment.mainDispatcher)
                            .map { ._coreDataSyncResult($0) },
                        
                        environment.feedbackLogger.log(
                            .info, "Speed Boost purchased successfully: '\(purchasedProduct)'")
                            .mapNever(),
                        
                        .fireAndForget {
                            environment.objcBridgeDelegate?.dismiss(screen: .psiCash,
                                                                    completion: nil)
                        }
                        
                    ]
                    
                }
                
            case let .failure(parseError):
                // Programming error
                environment.feedbackLogger.fatalError("failed to parse purchase: '\(parseError)'")
                return []
                
            }
            
        case let .failure(errorEvent):
            
            state.psiCash.purchase = .error(errorEvent)
            
            var effects = [Effect<PsiCashAction>]()
            
            // Refreshes PsiCash state if any of these conditions is true, followed by reasoning:
            // - Catastrphic network error:
            //     The purchase succeeded on the server side but wasn't retrieved.
            // - TransactionAmountMismatch:
            //     The price list should be updated immediately.
            // - TransactionTypeNotFound:
            //     The price list should be updated immediately, but it might also
            //     indicate an out-of-date app.
            // - InvalidTokens:
            //     Current tokens are invalid (e.g. user needs to log back in).
            
            switch errorEvent.error {
            case .requestError(.requestCatastrophicFailure(_)),
                    .requestError(.errorStatus(.transactionAmountMismatch)),
                    .requestError(.errorStatus(.transactionTypeNotFound)),
                    .requestError(.errorStatus(.invalidTokens)):
                
                effects += Effect(value: .refreshPsiCashState())
                
            case .tunnelNotConnected,
                    .requestError(.errorStatus(.existingTransaction)),
                    .requestError(.errorStatus(.insufficientBalance)),
                    .requestError(.errorStatus(.serverError)):
                // Not RefreshState required.
                break
            }
            
            effects += environment.feedbackLogger.log(.error, errorEvent).mapNever()

            return effects
        }
        
    case let .refreshPsiCashState(ignoreSubscriptionState):
        
        guard
            case .success(_) = state.psiCash.libData,
            let tunnelConnection = state.tunnelConnection,
            case .completed(_) = state.psiCash.pendingPsiCashRefresh
        else {
            return []
        }

        if !ignoreSubscriptionState {
            guard case .notSubscribed = state.subscription.status else {
                return []
            }
        }
        
        state.psiCash.pendingPsiCashRefresh = .pending
        
        return [
            environment.feedbackLogger.log(.info, "PsiCash: refresh state started").mapNever(),
            environment.psiCashEffects
                .refreshState(priceClasses: PsiCashTransactionClass.allCases,
                              tunnelConnection: tunnelConnection,
                              clientMetaData: environment.metadata())
                .map(PsiCashAction._refreshPsiCashStateResult)
        ]
        
    case ._refreshPsiCashStateResult(let result):
        
        guard case .pending = state.psiCash.pendingPsiCashRefresh else {
            environment.feedbackLogger.fatalError("unexpected state")
            return []
        }
        
        state.psiCash.pendingPsiCashRefresh = .completed(result.successToUnit().toUnit())
        
        switch result {
        case .success(let refreshStateResponse):
            
            state.psiCash.libData = .success(refreshStateResponse.libData)
            state.psiCashBalance = .refreshed(refreshedData: refreshStateResponse.libData,
                                              persisted: environment.psiCashPersistedValues)
            
            return [
                
                // If there is any Speed Boost authoriztions, it is persisted with Core Data.
                environment.sharedAuthCoreData
                    .syncAuthorizationsWithSharedCoreData(
                        Authorization.AccessType.speedBoostTypes,
                        state.psiCash.getSharedAuthorizationModels(),
                        environment.mainDispatcher)
                    .map { ._coreDataSyncResult($0) },
                
                environment.feedbackLogger.log(.info, "PsiCash: refresh state success").mapNever()
            ]
            
        case .failure(let error):
            return [
                environment.feedbackLogger.log(
                    .warn,
                    LogMessage(stringLiteral:"PsiCash: refresh state error: " + String(describing: error))
                ).mapNever()
            ]
        }
        
    case .accountLogout:
        
        guard case .success(_) = state.psiCash.libData else {
            fatalError()
        }
        
        if let pendingAccountLogin = state.psiCash.pendingAccountLoginLogout {
            // Guards against another request being send whilst one is in progress.
            guard case .completed(_) = pendingAccountLogin.wrapped else {
                return [
                    environment.feedbackLogger.log(
                        .warn, "another login/logout request is in flight").mapNever()
                ]
            }
        }
        
        guard case .account(loggedIn: true) = state.psiCash.libData?.successToOptional()?.accountType else {
            return [
                environment.feedbackLogger.log(.warn ,"""
                    User is not logged in: \
                    '\(String(describing: state.psiCash.libData?.successToOptional()?.accountType))'
                    """).mapNever()
            ]
        }
        
        state.psiCash.pendingAccountLoginLogout = Event(.pending(.logout),
                                                        date: environment.getCurrentTime())
        
        return [
            
            // Clears webview cache and storage.
            // This clears everything and does not target PsiCash account management website
            // data. This is not an issue for now at least, since webviews are not
            // used anywhere else in the app.
            environment.clearWebViewDataStore().mapNever(),
            
            environment.psiCashEffects.accountLogout()
                .map(PsiCashAction._accountLogoutResult),
            
        ]
        
    case ._accountLogoutResult(let result):
        guard
            let pendingAccountLoginLogout = state.psiCash.pendingAccountLoginLogout,
            case .pending(.logout) = pendingAccountLoginLogout.wrapped
        else {
            environment.feedbackLogger.fatalError("expected '.pending(.logout)' state")
            return []
        }
                
        state.psiCash.pendingAccountLoginLogout = Event(.completed(.right(result)),
                                                        date: environment.getCurrentTime())
        
        switch result {
        case .success(let logoutResponse):
            
            state.psiCash.libData = .success(logoutResponse.libData)
            state.psiCashBalance = .refreshed(refreshedData: logoutResponse.libData,
                                              persisted: environment.psiCashPersistedValues)

            return [
                // Updates persisted authorizations with Core Data (i.e. they are removed).
                environment.sharedAuthCoreData
                    .syncAuthorizationsWithSharedCoreData(
                        Authorization.AccessType.speedBoostTypes,
                        state.psiCash.getSharedAuthorizationModels(),
                        environment.mainDispatcher)
                    .map { ._coreDataSyncResult($0) }
            ]
            
        case .failure(let error):
            state.psiCash.libData = environment.psiCashEffects.libData()
            return [
                environment.feedbackLogger.log(.error, error).mapNever()
            ]
        }
        
    case let .accountLogin(username, password):
        
        guard case .success(_) = state.psiCash.libData else {
            return [
                environment.feedbackLogger.log(.error, "PsiCash lib is not initialized")
                    .mapNever()
            ]
        }
        
        if let pendingAccountLogin = state.psiCash.pendingAccountLoginLogout {
            // Guards against another request being send whilst one is in progress.
            guard case .completed(_) = pendingAccountLogin.wrapped else {
                return [
                    environment.feedbackLogger.log(
                        .warn,
                        "another login/logout request is in flight").mapNever()
                ]
            }
        }
        
        guard let tunnelConnection = state.tunnelConnection else {
            return [
                environment.feedbackLogger.log(.error, "tunnel connection is nil")
                    .mapNever()
            ]
        }
        
        state.psiCash.pendingAccountLoginLogout = Event(.pending(.login),
                                                        date: environment.getCurrentTime())
        
        return [
            environment.psiCashEffects
                .accountLogin(tunnelConnection: tunnelConnection,
                              username: username,
                              password: password)
                .map(PsiCashAction._accountLoginResult)
        ]
    
    case ._accountLoginResult(let result):
        guard
            let pendingAccountLoginLogout = state.psiCash.pendingAccountLoginLogout,
            case .pending(.login) = pendingAccountLoginLogout.wrapped
        else {
            environment.feedbackLogger.fatalError("expected '.pending(.login)' state")
            return []
        }
                
        state.psiCash.pendingAccountLoginLogout = Event(.completed(.left(result)),
                                                        date: environment.getCurrentTime())
        
        state.psiCash.libData = environment.psiCashEffects.libData()
        
        var effects = [Effect<PsiCashAction>]()
        
        // Refresh PsiCash state (regardless of whether login was successful or not.)
        effects += Effect(value: .refreshPsiCashState())
        
        switch result {
        case .success(let accountLoginResponse):
            effects += environment.feedbackLogger.log(
                .info, "account login completed: '\(accountLoginResponse)'"
            ).mapNever()
            
        case .failure(let errorEvent):
            effects += environment.feedbackLogger.log(.error, errorEvent).mapNever()
        }
        
        return effects
        
    case .dismissedAlert(let dismissed):
        switch dismissed {
        case .speedBoostAlreadyActive:
            state.psiCash.purchase = .none
            return []
        }
        
    case let .userDidEarnReward(rewardAmount, reason):
        
        // Increases displayed PsiCash balance optimistically
        // with the given rewardAmount, until PsiCash state is refreshed.
        
        state.psiCashBalance.waitingForExpectedIncrease(
            withAddedReward: rewardAmount,
            reason: reason,
            persisted: environment.psiCashPersistedValues)
        
        return [ Effect(value: .refreshPsiCashState()) ]
        
    case ._coreDataSyncResult(let syncResult):
        
        // Notifies the Network Extension of any changes to persisted authorization in Core Data.
        // Errors with Core Data are only logged, and no further action is taken at this point.
        
        switch syncResult {
            
        case .success(let changed):
            
            var effects = [Effect<PsiCashAction>]()
            
            if changed {
                // Notifies Network Extension if any changes have been made to the peristent store.
                effects += .fireAndForget {
                    environment.notifier.post(environment.notifierUpdatedAuthorizationsMessage)
                }
            }
            
            effects += environment.feedbackLogger.log(
                .info, "Synced PsiCash authorizations with Core Data")
                .mapNever()
            
            return effects
            
        case .failure(let error):
            
            return [
                environment.feedbackLogger.log(
                    .error, "Failed to sync PsiCash authorization with Core Data: \(error)"
                ).mapNever()
            ]
        }
        
    case ._forceRemovedPurchases(let result):
        
        // Logs result of force removal of PsiCash purchases.
        
        switch result {
            
        case .success(let products):
            
            return [
                environment.feedbackLogger.log(
                    .info, "Force removed PsiCash transactions: \(products)")
                    .mapNever()
            ]
            
        case .failure(let error):
            
            return [
                environment.feedbackLogger.log(
                    .error, "Failed to force-remove PsiCash transactions: \(error)")
                    .mapNever()
            ]
            
        }
        
    }
}

// MARK: Helper functions

extension PsiCashState {
    
    /// Set of SharedAuthorizationModel values for all  in `transactionsAuthState`
    /// that have an authorization.
    /// - Note: `psiphondRejected` is set to `false`.
    func getSharedAuthorizationModels() -> Set<SharedAuthorizationModel> {
        Set(
            libData?.successToOptional()?.activePurchases.compactMap {
                switch $0 {
                case .success(.speedBoost(let product)):
                    return SharedAuthorizationModel(
                        authorization: product.transaction.authorization,
                        webOrderLineItemID: .none,
                        psiphondRejected: false
                    )
                case .failure(_):
                    return nil
                }
            } ?? []
        )
    }
    
    /// For PsiCash purchases that have an authorization, return the list of purchases
    /// that matches the provded authorization ids.
    func getPurchases(
        forAuthorizaitonIDs authIds: [AuthorizationID]
    ) -> [PurchasedExpirableProduct<SpeedBoostProduct>] {
        libData?.successToOptional()?.activePurchases.compactMap { purchase -> PurchasedExpirableProduct<SpeedBoostProduct>? in
            switch purchase {
            case .success(.speedBoost(let product)):
                let found = authIds.contains {
                    $0 == product.transaction.authorization.decoded.authorization.id
                }
                if found {
                    return product
                } else {
                    return nil
                }
            case .failure(_):
                return nil
            }
        } ?? []
    }
    
}
