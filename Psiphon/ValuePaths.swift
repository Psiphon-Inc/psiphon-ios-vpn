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
import Promises

// MARK: Application.swift

extension AppAction {

    var appDelegateAction: AppDelegateAction? {
        get {
            guard case let .appDelegateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .appDelegateAction = self, let newValue = newValue else { return }
            self = .appDelegateAction(newValue)
        }
    }
    
    var psiCash: PsiCashAction? {
        get {
            guard case let .psiCash(value) = self else { return nil }
            return value
        }
        set {
            guard case .psiCash = self, let newValue = newValue else { return }
            self = .psiCash(newValue)
        }
    }
    
    var landingPage: LandingPageAction? {
        get {
            guard case let .landingPage(value) = self else { return nil }
            return value
        }
        set {
            guard case .landingPage = self, let newValue = newValue else { return }
            self = .landingPage(newValue)
        }
    }
    
    var inAppPurchase: IAPAction? {
        get {
            guard case let .iap(value) = self else { return nil }
            return value
        }
        set {
            guard case .iap = self, let newValue = newValue else { return }
            self = .iap(newValue)
        }
    }
    
    var appReceipt: ReceiptStateAction? {
        get {
            guard case let .appReceipt(value) = self else { return nil }
            return value
        }
        set {
            guard case .appReceipt = self, let newValue = newValue else { return }
            self = .appReceipt(newValue)
        }
    }
    
    var subscription: SubscriptionAction? {
        get {
            guard case let .subscription(value) = self else { return nil }
            return value
        }
        set {
            guard case .subscription = self, let newValue = newValue else { return }
            self = .subscription(newValue)
        }
    }
    
    var productRequest: ProductRequestAction? {
        get {
            guard case let .productRequest(value) = self else { return nil }
            return value
        }
        set {
            guard case .productRequest = self, let newValue = newValue else { return }
            self = .productRequest(newValue)
        }
    }

}


extension AppState {
    
    var iapReducerState: IAPReducerState {
        get {
            IAPReducerState(
                iap: self.iapState,
                psiCashBalance: self.psiCashBalance,
                psiCashAuth: self.psiCash.libData.authPackage
            )
        }
        set {
            self.iapState = newValue.iap
            self.psiCashBalance = newValue.psiCashBalance
        }
    }
    
    var psiCashReducerState: PsiCashReducerState {
        get {
            PsiCashReducerState(
                psiCashBalance: self.psiCashBalance,
                psiCash: self.psiCash,
                subscription: self.subscription
            )
        }
        set {
            self.psiCashBalance = newValue.psiCashBalance
            self.psiCash = newValue.psiCash
        }
    }
    
    var appDelegateReducerState: AppDelegateReducerState {
        get {
            AppDelegateReducerState(
                psiCashBalance: self.psiCashBalance,
                psiCash: self.psiCash
            )
        }
        set {
            self.psiCashBalance = newValue.psiCashBalance
            self.psiCash = newValue.psiCash
        }
    }
    
    var landingPageReducerState: LandingPageReducerState {
        get {
            LandingPageReducerState(
                shownLandingPage: shownLandingPage,
                activeSpeedBoost: psiCash.activeSpeedBoost
            )
        }
        set {
            shownLandingPage = newValue.shownLandingPage
        }
    }
    
    var psiCashViewController: PsiCashViewControllerState {
        PsiCashViewControllerState(
            psiCashBalance: self.psiCashBalance,
            psiCash: self.psiCash,
            iap: self.iapState,
            subscription: self.subscription,
            appStorePsiCashProducts: self.products.psiCashProducts
        )
    }
    
    var balanceState: BalanceState {
        BalanceState(
            psiCashState: self.psiCash,
            balance: self.psiCashBalance
        )
    }
}

// MARK: IAPState.swift

extension IAPPaymentType {
    
    var paymentObject: SKPayment {
        switch self {
        case .psiCash(let value):
            return value
        case .subscription(let value, _):
            return value
        }
    }
    
}

// MARK: IAPState.swift

extension IAPPurchasableProduct {
    var appStoreProduct: AppStoreProduct {
        switch self {
        case let .psiCash(product: product): return product
        case let .subscription(product: product, promise: _): return product
        }
    }
}
