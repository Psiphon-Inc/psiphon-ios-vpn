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
import PsiApi
import AppStoreIAP
import PsiCashClient

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
    
    var subscriptionAuthStateAction: SubscriptionAuthStateAction? {
        get {
            guard case let .subscriptionAuthStateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .subscriptionAuthStateAction = self, let newValue = newValue else { return }
            self = .subscriptionAuthStateAction(newValue)
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

    var reachabilityAction: ReachabilityAction? {
        get {
            guard case let .reachabilityAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .reachabilityAction = self, let newValue = newValue else { return }
            self = .reachabilityAction(newValue)
        }
    }
    
    var vpnStateAction: VPNStateAction<PsiphonTPM>? {
        get {
            guard case let .vpnStateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .vpnStateAction = self, let newValue = newValue else { return }
            self = .vpnStateAction(newValue)
        }
    }

    var feedbackAction: FeedbackAction? {
        get {
            guard case let .feedbackAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .feedbackAction = self, let newValue = newValue else { return }
            self = .feedbackAction(newValue)
        }
    }
    
    var mainViewAction: MainViewAction? {
        get {
            guard case let .mainViewAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .mainViewAction = self, let newValue = newValue else { return }
            self = .mainViewAction(newValue)
        }
    }
}


extension AppState {
    
    /// `tunnelConnection` returns a TunnelConnection object holding a weak reference to the underlying
    ///  TunnelProviderManager reference if it exists.
    var tunnelConnection: TunnelConnection? {
        get {
            guard case let .loaded(tpm) = self.vpnState.value.loadState.value else {
                return nil
            }
            return tpm.connection
        }
    }
    
    var vpnReducerState: VPNReducerState<PsiphonTPM> {
        // TODO: This can be simplified by a new `SerialEffectState` constructor.
        get {
            VPNReducerState(
                pendingActionQueue: self.vpnState.pendingActionQueue,
                pendingEffectActionQueue: self.vpnState.pendingEffectActionQueue,
                pendingEffectCompletion: self.vpnState.pendingEffectCompletion,
                value: VPNProviderManagerReducerState (
                    vpnState: self.vpnState.value,
                    subscriptionTransactionsPendingAuthorization:
                    self.subscriptionAuthState .transactionsPendingAuthRequest
                )
            )
        }
        set {
            self.vpnState.pendingActionQueue = newValue.pendingActionQueue
            self.vpnState.pendingEffectActionQueue = newValue.pendingEffectActionQueue
            self.vpnState.pendingEffectCompletion = newValue.pendingEffectCompletion
            self.vpnState.value = newValue.value.vpnState
        }
    }
    
    var iapReducerState: IAPReducerState {
        get {
            IAPReducerState(
                iap: self.iapState,
                psiCashBalance: self.psiCashBalance,
                psiCashAccountType: self.psiCash.libData.accountType
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
                subscription: self.subscription,
                tunnelConnection: self.tunnelConnection
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
                pendingLandingPageOpening: self.pendingLandingPageOpening,
                tunnelConnection: self.tunnelConnection
            )
        }
        set {
            self.pendingLandingPageOpening = newValue.pendingLandingPageOpening
        }
    }
    
    var subscriptionAuthReducerState: SubscriptionReducerState {
        get {
            SubscriptionReducerState(
                subscription: self.subscriptionAuthState,
                receiptData: self.appReceipt.receiptData
            )
        }
        set {
            self.subscriptionAuthState = newValue.subscription
        }
    }
    
    var psiCashViewControllerReaderState: PsiCashViewController.ReaderState {
        PsiCashViewController.ReaderState(
            mainViewState: self.mainView,
            psiCashBalanceViewModel: self.psiCashBalanceViewModel,
            psiCash: self.psiCash,
            iap: self.iapState,
            subscription: self.subscription,
            appStorePsiCashProducts: self.products.psiCashProducts,
            isRefreshingAppStoreReceipt: self.appReceipt.isRefreshingReceipt
        )
    }
    
    var psiCashBalanceViewModel: PsiCashBalanceViewModel {
        PsiCashBalanceViewModel(
            psiCashLibLoaded: self.psiCash.libLoaded,
            balanceState: self.balanceState
        )
    }
    
    var balanceState: BalanceState {
        BalanceState(
            pendingPsiCashRefresh: self.psiCash.pendingPsiCashRefresh,
            psiCashBalance: self.psiCashBalance
        )
    }

    var feedbackReducerState: FeedbackReducerState {
        get {
            FeedbackReducerState(
                queuedFeedbacks: self.queuedFeedbacks
            )
        }
        set {
            self.queuedFeedbacks = newValue.queuedFeedbacks
        }
    }
    
    var mainViewReducerState: MainViewReducerState {
        get {
            MainViewReducerState(
                mainView: self.mainView,
                psiCashAccountType: self.psiCash.libData.accountType
            )
        }
        set {
            self.mainView = newValue.mainView
        }
    }
    
}
