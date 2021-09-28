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
import ReactiveSwift


/// Container for result of PsiCash library initialization, used by `PsiCashEffectsProtocol`.
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

/// Container for result of a new expiring purchase, used by `PsiCashEffectsProtocol`.
public struct NewExpiringPurchaseResult: Equatable {

    public typealias ErrorType =
        ErrorEvent<TunneledPsiCashRequestError<PsiCashNewExpiringPurchaseError>>

    public let refreshedLibData: PsiCashLibData
    public let result: Result<NewExpiringPurchaseResponse, ErrorType>

    public init(
        refreshedLibData: PsiCashLibData,
        result: Result<NewExpiringPurchaseResponse, ErrorType>
    ) {
        self.refreshedLibData = refreshedLibData
        self.result = result
    }
    
}

/// Defines an interface of PsiCash side-effects to be consumed by a Reducer that manages
/// PsiCash state in the app.
/// TODO: Once actors are introduced in the language, they're better suited for defining of side-effects.
public protocol PsiCashEffectsProtocol {
    
    typealias PsiCashInitResult = Result<PsiCashLibInitSuccess, ErrorRepr>
        
    typealias PsiCashRefreshResult = Result<RefreshStateResponse, ErrorEvent<PsiCashRefreshError>>
    
    typealias PsiCashAccountLoginResult =
        Result<AccountLoginResponse,
               ErrorEvent<TunneledPsiCashRequestError<PsiCashAccountLoginError>>>
    
    typealias PsiCashAccountLogoutResult =
        Result<AccountLogoutResponse,
                ErrorEvent<PsiCashLibError>>
    
    /// Initializes PsiCash client lib given path of file store root directory.
    func initialize(
        fileStoreRoot: String?,
        psiCashLegacyDataStore: UserDefaults,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    ) -> Effect<PsiCashInitResult>
    
    func libData() -> PsiCashLibData
    
    func refreshState(
        priceClasses: [PsiCashTransactionClass],
        tunnelConnection: TunnelConnection,
        clientMetaData: ClientMetaData
    ) -> Effect<PsiCashRefreshResult>
    
    func purchaseProduct(
        purchasable: PsiCashPurchasableType,
        tunnelConnection: TunnelConnection,
        clientMetaData: ClientMetaData
    ) -> Effect<NewExpiringPurchaseResult>
    
    func modifyLandingPage(_ url: URL) -> Effect<URL>
    
    func rewardedVideoCustomData() -> String?
    
    func removePurchases(withTransactionIDs: [String]) ->
    Effect<Result<[PsiCashParsed<PsiCashPurchasedType>], PsiCashLibError>>
    
    func accountLogout() -> Effect<PsiCashAccountLogoutResult>
    
    func accountLogin(
        tunnelConnection: TunnelConnection,
        username: String,
        password: SecretString
    ) -> Effect<PsiCashAccountLoginResult>
 
    func setLocale(_ locale: Locale) -> Effect<Never>
    
}
