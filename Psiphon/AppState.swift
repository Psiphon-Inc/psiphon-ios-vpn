/*
 * Copyright (c) 2019, Psiphon Inc.
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

/// Represents UIViewController's that can be dismissed.
@objc enum DismissableScreen: Int {
    case psiCash
}

struct AppState: Equatable {
    var psiCashBalance = PsiCashBalance()
    var shownLandingPage = LandingPageShownState.notShown
    var psiCash = PsiCashState()
    var appReceipt = ReceiptState()
    var subscription = SubscriptionState()
    var iapState = IAPState()
    var products = PsiCashAppStoreProductsState()
}

struct BalanceState: Equatable {
    let pendingPsiCashRefresh: PendingPsiCashRefresh
    let psiCashBalance: PsiCashBalance
    
    init(psiCashState: PsiCashState, balance: PsiCashBalance) {
        self.pendingPsiCashRefresh = psiCashState.pendingPsiCashRefresh
        self.psiCashBalance = balance
    }
}
 
// MARK: AppAction

enum AppAction {
    case appDelegateAction(AppDelegateAction)
    case psiCash(PsiCashAction)
    case landingPage(LandingPageAction)
    case iap(IAPAction)
    case appReceipt(ReceiptStateAction)
    case subscription(SubscriptionAction)
    case productRequest(ProductRequestAction)
}

// MARK: Application

let appReducer: Reducer<AppState, AppAction> =
    combine(
        pullback(psiCashReducer, value: \.psiCashReducerState, action: \.psiCash),
        pullback(landingPageReducer, value: \.landingPageReducerState, action: \.landingPage),
        pullback(iapReducer, value: \.iapReducerState, action: \.inAppPurchase),
        pullback(receiptReducer, value: \.appReceipt, action: \.appReceipt),
        pullback(subscriptionReducer, value: \.subscription, action: \.subscription),
        pullback(productRequestReducer, value: \.products, action: \.productRequest),
        pullback(appDelegateReducer, value: \.appDelegateReducerState, action: \.appDelegateAction)
)

/// Represents an application that has finished loading.
final class Application {
    private(set) var store: Store<AppState, AppAction>

    /// - Parameter objcHandler: Handles `ObjcAction` type. Always called from the main thread.
    init(initalState: AppState, reducer: @escaping Reducer<AppState, AppAction>) {
        self.store = Store(initialValue: initalState, reducer: reducer)
    }

}
