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
    let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    // TODO: Remove this dependency from reducer's environment. UI-related effects
    // unnecessarily complicate reducers.
    let objcBridgeDelegate: ObjCBridgeDelegate?
    let metadata: () -> ClientMetaData
    let getCurrentTime: () -> Date
    let psiCashLegacyDataStore: UserDefaults
    let userConfigs: UserDefaultsConfig
    let mainDispatcher: MainDispatcher
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
            state.psiCash.libData = libInitSuccess.libData
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
                
                // TODO!! confirm that this whole effect is working properly.
                
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
            return [
                environment.feedbackLogger.log(.error, "failed to initialize PsiCash: \(error)")
                    .mapNever()
            ]
        }
    
    case .setLocale(let locale):
        
        // PsiCash Library must be initialized before setting locale.
        guard state.psiCash.libData != nil else {
            environment.feedbackLogger.fatalError("lib not loaded")
            return []
        }
        
        return [
            environment.psiCashEffects.setLocale(locale)
                .mapNever()
        ]
        
    case .buyPsiCashProduct(let purchasableType):
        
        guard
            state.psiCash.libData != nil,
            let tunnelConnection = state.tunnelConnection,
            case .notSubscribed = state.subscription.status,
            state.psiCash.purchasing.completed
        else {
            return []
        }
        
        guard let purchasable = purchasableType.speedBoost else {
            environment.feedbackLogger.fatalError(
                "Expected a PsiCashPurchasable in '\(purchasableType)'")
            return []
        }
        state.psiCash.purchasing = .speedBoost(purchasable)
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
        
        
    case let ._psiCashProductPurchaseResult(purchasable, purchaseResult):
        
        guard case .speedBoost(_) = state.psiCash.purchasing else {
            environment.feedbackLogger.fatalError("""
                Expected '.speedBoost' state:'\(String(describing: state.psiCash.purchasing))'
                """)
            return []
        }
        
        guard purchasable.speedBoost != nil else {
            environment.feedbackLogger.fatalError("""
                Expected '.speedBoost'; purchasable: '\(purchasable)'
                """)
            return []
        }

        state.psiCash.libData = purchaseResult.refreshedLibData
        state.psiCashBalance = .refreshed(refreshedData: purchaseResult.refreshedLibData,
                                          persisted: environment.psiCashPersistedValues)

        switch purchaseResult.result {
        case let .success(newExpiringPurchaseResponse):
            
            switch newExpiringPurchaseResponse.purchasedType {
            
            case let .success(purchasedType):
                
                switch purchasedType {
                    
                case .speedBoost(let purchasedProduct):
                    
                    state.psiCash.purchasing = .none
                    
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
            state.psiCash.purchasing = .error(errorEvent)
            return [ environment.feedbackLogger.log(.error, errorEvent).mapNever() ]
        }
        
    case let .refreshPsiCashState(ignoreSubscriptionState):
        
        guard
            state.psiCash.libData != nil,
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
            
            state.psiCash.libData = refreshStateResponse.libData
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
        
        if let pendingAccountLogin = state.psiCash.pendingAccountLoginLogout {
            // Guards against another request being send whilst one is in progress.
            guard case .completed(_) = pendingAccountLogin.wrapped else {
                return [
                    environment.feedbackLogger.log(
                        .warn, "another login/logout request is in flight").mapNever()
                ]
            }
        }
        
        guard case .account(loggedIn: _) = state.psiCash.libData?.accountType else {
            return [
                environment.feedbackLogger.log(.warn ,"""
                    user is not an account: \
                    '\(String(describing: state.psiCash.libData?.accountType))'
                    """).mapNever()
            ]
        }
        
        state.psiCash.pendingAccountLoginLogout = Event(.pending(.logout),
                                                        date: environment.getCurrentTime())
        
        return [
            environment.psiCashEffects.accountLogout()
                .map(PsiCashAction._accountLogoutResult)
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
            
            state.psiCash.libData = logoutResponse.libData
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
        
        switch result {
        case .success(let accountLoginResponse):
            return [
                // Refreshes PsiCash state immediately after successful login.
                Effect(value: .refreshPsiCashState()),
                
                environment.feedbackLogger.log(
                    .info, "account login completed: '\(accountLoginResponse)'"
                ).mapNever()
            ]
            
        case .failure(let errorEvent):
            return [
                environment.feedbackLogger.log(.error, errorEvent).mapNever()
            ]
        }
        
    case .dismissedAlert(let dismissed):
        switch dismissed {
        case .speedBoostAlreadyActive:
            state.psiCash.purchasing = .none
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
        
    case .connectToPsiphonTapped:
        return [
            .fireAndForget { [unowned objcBridgeDelegate = environment.objcBridgeDelegate] in
                objcBridgeDelegate?.dismiss(screen: .psiCash, completion: {
                    objcBridgeDelegate?.startStopVPN()
                })
            }
        ]
        
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
            libData?.activePurchases.compactMap {
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
        libData?.activePurchases.compactMap { purchase -> PurchasedExpirableProduct<SpeedBoostProduct>? in
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
