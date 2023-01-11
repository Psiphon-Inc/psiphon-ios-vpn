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
import AppStoreIAP

extension AppState {
    
    /// `tunnelConnection` returns a TunnelConnection object holding a weak reference to the underlying
    ///  TunnelProviderManager reference if it exists.
    var tunnelConnection: TunnelConnection? {
        get {
            // Workaround, since VPN config cannot be installed on a simulator.
            #if targetEnvironment(simulator)
            return TunnelConnection { () -> TunnelConnection.ConnectionResourceStatus in
                return .connection(.connected)
            }
            #else
            guard case let .loaded(tpm) = self.vpnState.value.loadState.value else {
                return nil
            }
            return tpm.connection
            #endif
        }
    }
    
    var vpnReducerState: VPNReducerState<PsiphonTPM> {
        get {
            VPNReducerState(
                pendingActionQueue: self.vpnState.pendingActionQueue,
                pendingEffectActionQueue: self.vpnState.pendingEffectActionQueue,
                pendingEffectCompletion: self.vpnState.pendingEffectCompletion,
                value: VPNProviderManagerReducerState (
                    vpnState: self.vpnState.value,
                    anySubscriptionTxPendingAuthorization:
                        self.subscriptionAuthState.anyPendingAuthRequests
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
                receiptData: self.appReceipt.receiptData,
                psiCashBalance: self.psiCashBalance,
                psiCashAccountType: self.psiCashState.libData?.successToOptional()?.accountType
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
                psiCash: self.psiCashState,
                subscription: self.subscription,
                tunnelConnection: self.tunnelConnection
            )
        }
        set {
            self.psiCashBalance = newValue.psiCashBalance
            self.psiCashState = newValue.psiCash
        }
    }
    
    var appDelegateReducerState: AppDelegateReducerState {
        get {
            AppDelegateReducerState(
                appDelegateState: self.appDelegateState,
                subscriptionState: self.subscription,
                psiCashState: self.psiCashState,
                tunnelConnectedStatus: self.vpnState.value.providerVPNStatus.tunneled
            )
        }
        set {
            self.appDelegateState = newValue.appDelegateState
        }
    }
    
    var landingPageReducerState: LandingPageReducerState {
        get {
            LandingPageReducerState(
                pendingLandingPageOpening: self.pendingLandingPageOpening,
                tunnelConnection: self.tunnelConnection,
                applicationParameters: self.appDelegateState.applicationParameters,
                psiCashState: self.psiCashState,
                subscriptionState: self.subscription
            )
        }
        set {
            self.pendingLandingPageOpening = newValue.pendingLandingPageOpening
        }
    }
    
    var psiCashStoreViewControllerReaderState: PsiCashStoreViewController.ReaderState {
        PsiCashStoreViewController.ReaderState(
            mainViewState: self.mainView,
            psiCashBalanceViewModel: self.psiCashBalanceViewModel,
            psiCash: self.psiCashState,
            iap: self.iapState,
            subscription: self.subscription,
            appStorePsiCashProducts: self.products.psiCashProducts,
            isRefreshingAppStoreReceipt: self.appReceipt.isRefreshingReceipt
        )
    }
    
    var psiCashBalanceViewModel: PsiCashBalanceViewModel {
        PsiCashBalanceViewModel(
            psiCashLibLoaded: self.psiCashState.libData != nil,
            balanceState: self.balanceState
        )
    }
    
    var balanceState: BalanceState {
        BalanceState(
            pendingPsiCashRefresh: self.psiCashState.pendingPsiCashRefresh,
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
                subscriptionState: self.subscription,
                psiCashState: self.psiCashState,
                psiCashAccountType: self.psiCashState.libData?.successToOptional()?.accountType,
                appLifecycle: self.appDelegateState.appLifecycle,
                tunnelConnectedStatus: self.vpnState.value.providerVPNStatus.tunneled,
                applicationParameters: self.appDelegateState.applicationParameters
            )
        }
        set {
            self.mainView = newValue.mainView
        }
    }
    
}
