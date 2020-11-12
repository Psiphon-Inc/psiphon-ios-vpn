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
import PsiApi


/// Container for all PsiCash effects.
/// Instances of this type probably wrap some kind of cross-platform PsiCash client library.
public struct PsiCashEffects {
    
    public typealias PsiCashRefreshResult =
        Result<PsiCashLibData,
               ErrorEvent<TunneledPsiCashRequestError<PsiCashRefreshError>>>
    
    public typealias PsiCashAccountLoginResult =
        Result<AccountLoginResponse,
               ErrorEvent<TunneledPsiCashRequestError<PsiCashAccountLoginError>>>
    
    public typealias PsiCashAccountLogoutResult =
        Result<PsiCashLibData,
                ErrorEvent<TunneledPsiCashRequestError<PsiCashLibError>>>

    /// Represents success reuslt of PsiCash client lib initialization.
    public struct PsiCashLibInitSuccess: Equatable {
        public let libData: PsiCashLibData
        public let requiresStateRefresh: Bool

        public init(
            libData: PsiCashLibData,
            requiresStateRefresh: Bool
        ) {
            self.libData = libData
            self.requiresStateRefresh = requiresStateRefresh
        }

    }

    public struct NewExpiringPurchaseResult: Equatable {

        public typealias ErrorType =
            ErrorEvent<TunneledPsiCashRequestError<PsiCashNewExpiringPurchaseError>>

        public let refreshedLibData: PsiCashLibData
        public let result: Result<NewExpiringPurchaseResponse, ErrorType>

        public init(
            refreshedLibData: PsiCashLibData,
            result: Result<NewExpiringPurchaseResponse,
                           PsiCashEffects.NewExpiringPurchaseResult.ErrorType>
        ) {
            self.refreshedLibData = refreshedLibData
            self.result = result
        }
    }
    
    /// Initializes PsiCash client lib given path of file store root directory.
    public let initialize: (String?, UserDefaults) -> Effect<Result<PsiCashLibInitSuccess, ErrorRepr>>
    public let libData: () -> PsiCashLibData
    public let refreshState: ([PsiCashTransactionClass], TunnelConnection, ClientMetaData) ->
        Effect<PsiCashRefreshResult>
    public let purchaseProduct: (PsiCashPurchasableType, TunnelConnection, ClientMetaData) ->
        Effect<NewExpiringPurchaseResult>
    public let modifyLandingPage: (URL) -> Effect<URL>
    public let rewardedVideoCustomData: () -> String?
    public let removePurchasesNotIn: (Set<String>) -> Effect<Never>
    public let accountLogout: (TunnelConnection) -> Effect<PsiCashAccountLogoutResult>
    public let accountLogin: (TunnelConnection, String, SecretString) -> Effect<PsiCashAccountLoginResult>

    public init(
        initialize: @escaping (String?, UserDefaults)
            -> Effect<Result<PsiCashLibInitSuccess, ErrorRepr>>,
        libData: @escaping () -> PsiCashLibData,
        refreshState: @escaping ([PsiCashTransactionClass], TunnelConnection, ClientMetaData) ->
            Effect<PsiCashRefreshResult>,
        purchaseProduct: @escaping (PsiCashPurchasableType, TunnelConnection, ClientMetaData) ->
            Effect<NewExpiringPurchaseResult>,
        modifyLandingPage: @escaping (URL) -> Effect<URL>,
        rewardedVideoCustomData: @escaping () -> String?,
        removePurchasesNotIn: @escaping (Set<String>) -> Effect<Never>,
        accountLogout: @escaping (TunnelConnection) -> Effect<PsiCashAccountLogoutResult>,
        accountLogin:@escaping (TunnelConnection, String, SecretString) -> Effect<PsiCashAccountLoginResult>
    ) {
        self.initialize = initialize
        self.libData = libData
        self.refreshState = refreshState
        self.purchaseProduct = purchaseProduct
        self.modifyLandingPage = modifyLandingPage
        self.rewardedVideoCustomData = rewardedVideoCustomData
        self.removePurchasesNotIn = removePurchasesNotIn
        self.accountLogout = accountLogout
        self.accountLogin = accountLogin
    }
    
}
