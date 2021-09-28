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

public enum PsiCashAction: Equatable {

    case initialize

    /// Success result Bool represents whether a refresh state is required or not.
    case _initialized(PsiCashEffectsProtocol.PsiCashInitResult)
    
    case setLocale(Locale)
    
    case buyPsiCashProduct(PsiCashPurchasableType)
    case _psiCashProductPurchaseResult(
            purchasable: PsiCashPurchasableType,
            result: NewExpiringPurchaseResult
         )
    
    /// Performs a PsiCash RefreshState.
    ///  If `forced` is true, RefreshState action is taken whether or not the user is subscribed.
    case refreshPsiCashState(forced: Bool = false)
    case _refreshPsiCashStateResult(PsiCashEffectsProtocol.PsiCashRefreshResult)
    
    case accountLogout
    case _accountLogoutResult(PsiCashEffectsProtocol.PsiCashAccountLogoutResult)
    
    case accountLogin(username: String, password: SecretString)
    case _accountLoginResult(PsiCashEffectsProtocol.PsiCashAccountLoginResult)
    
    case userDidEarnReward(PsiCashAmount, PsiCashBalance.BalanceOutOfDateReason)
    
    case dismissedAlert(PsiCashAlertDismissAction)
    
    /// Represents result of syncing authorizations with Core Data.
    /// Boolean success result represents whether any changes have been made to the persistent store.
    case _coreDataSyncResult(Result<Bool, CoreDataError>)
    
    /// Result of force removal of PsiCash purchases from the PsiCash library.
    case _forceRemovedPurchases(Result<[PsiCashParsed<PsiCashPurchasedType>], PsiCashLibError>)
    
}

public enum PsiCashAlertDismissAction: Equatable {
    case speedBoostAlreadyActive
}
