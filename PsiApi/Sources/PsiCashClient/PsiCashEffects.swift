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
               ErrorEvent<TunneledPsiCashRequestError<
                            PsiCashRequestError<PsiCashRefreshErrorStatus>>>>
    
    public typealias PsiCashNewExpiringPurchaseResult =
        Result<NewExpiringPurchaseResponse,
               ErrorEvent<TunneledPsiCashRequestError<
                            PsiCashRequestError<PsiCashNewExpiringPurchaseErrorStatus>>>>
    
    public typealias PsiCashAccountLoginResult =
        Result<AccountLoginResponse,
               ErrorEvent<TunneledPsiCashRequestError<
                            PsiCashRequestError<PsiCashAccountLoginErrorStatus>>>>
    
    public typealias PsiCashAccountLogoutResult =
        Result<PsiCashLibData,
                ErrorEvent<TunneledPsiCashRequestError<PsiCashLibError>>>
    
    /// Initializes PsiCash client lib given path of file store root directory.
    public let initialize: (String?) -> Effect<Result<PsiCashLibData, ErrorRepr>>
    public let libData: () -> PsiCashLibData
    public let refreshState: ([PsiCashTransactionClass], TunnelConnection, ClientMetaData) ->
        Effect<PsiCashRefreshResult>
    public let purchaseProduct: (PsiCashPurchasableType, TunnelConnection, ClientMetaData) ->
        Effect<PsiCashNewExpiringPurchaseResult>
    public let modifyLandingPage: (URL) -> Effect<URL>
    public let rewardedVideoCustomData: () -> String?
    public let removePurchasesNotIn: (Set<String>) -> Effect<Never>
    public let accountLogout: (TunnelConnection) -> Effect<PsiCashAccountLogoutResult>
    public let accountLogin: (TunnelConnection, String, SecretString) -> Effect<PsiCashAccountLoginResult>

    public init(
        initialize: @escaping (String?) -> Effect<Result<PsiCashLibData, ErrorRepr>>,
        libData: @escaping () -> PsiCashLibData,
        refreshState: @escaping ([PsiCashTransactionClass], TunnelConnection, ClientMetaData) ->
            Effect<PsiCashRefreshResult>,
        purchaseProduct: @escaping (PsiCashPurchasableType, TunnelConnection, ClientMetaData) ->
            Effect<PsiCashNewExpiringPurchaseResult>,
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
