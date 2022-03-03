/*
 * Copyright (c) 2021, Psiphon Inc.
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
import PsiCashClient
import AppStoreIAP
import PsiphonClientCommonLibrary

#if DEBUG

/// Makes a reducer function for taking screenshots.
func makeUITestReducer() -> Reducer<AppState, AppAction, AppEnvironment> {
   
    Reducer.combine(
        mainViewReducer.pullback(
            value: \.mainViewReducerState,
            action: \.mainViewAction,
            environment: toMainViewReducerEnvironment(env:))
    )
    
}

/// App state for generating App Store screenshots.
func makeUITestAppState(embeddedServerEntriesFile: String) -> AppState {
    
    // NOTE: Assumes the price of each SB product is hrs * 100 PsiCash.
    let allSpeedBoostProducts = SpeedBoostDistinguisher.allCases.map { sbDistinguisher -> PsiCashPurchasableType in
        let sbProduct = SpeedBoostProduct(distinguisher: sbDistinguisher.rawValue)!
        let price = PsiCashAmount(nanoPsi: Int64(sbDistinguisher.hours) * 100_000_000_000)
        return .speedBoost(.init(product: sbProduct, price: price))
    }
    
    let psiCashBalance = PsiCashAmount(nanoPsi: 8_700_000_000_000)
    
    var error: NSError? = nil
    let embeddedRegions = EmbeddedServerEntries.egressRegions(fromFile: embeddedServerEntriesFile,
                                                              error: &error)
    RegionAdapter.sharedInstance().onAvailableEgressRegions(Array(embeddedRegions))
    let regions = (RegionAdapter.sharedInstance().getRegions() as! [Region])
    let regionCodes = Set(regions.compactMap { $0.code }) /* Set of available region codes */
    let selectedRegion = regions[0] /* Best performance region */
    
    return AppState(
        vpnState: VPNState<PsiphonTPM>(
            pendingActionQueue: .init(),
            pendingEffectActionQueue: .init(),
            pendingEffectCompletion: false,
            value: VPNProviderManagerState<PsiphonTPM>.init(
                tunnelIntent: .start(transition: .none),
                loadState: ProviderManagerLoadState<PsiphonTPM>.init(),
                providerVPNStatus: .connected /* Tunnel is connected */,
                startStopState: .none,
                providerSyncResult: .completed(.none)
            )
        ),
        psiCashBalance: .init(
            balanceOutOfDateReason: .none,
            optimisticBalance: psiCashBalance,
            lastRefreshBalance: psiCashBalance
        ),
        psiCashState: PsiCashState(
            purchasing: .none,
            libData: .success(PsiCashLibData(
                accountType: .account(loggedIn: true) /* User is logged in */,
                accountName: "open_internet_123" /* PsiCash Account username */,
                balance: psiCashBalance,
                availableProducts: allSpeedBoostProducts.map(Result.success),
                activePurchases: [])),
            pendingAccountLoginLogout: .none,
            pendingPsiCashRefresh: .completed(.success(.unit))
        ),
        appReceipt: .init(),
        subscription: SubscriptionState(status: .notSubscribed),
        subscriptionAuthState: .init(),
        iapState: .init(),
        products: .init(),
        pendingLandingPageOpening: false,
        internetReachability: ReachabilityState(networkStatus: .viaWiFi, codedStatus: .none),
        appDelegateState: AppDelegateState(
            appLifecycle: .didBecomeActive,
            pendingPresentingDisallowedTrafficAlert: false,
            onboardingCompleted: true
        ),
        queuedFeedbacks: [],
        mainView: MainViewState(
            alertMessages: Set(),
            psiCashStoreViewState: .none,
            psiCashAccountLoginIsPresented: .completed(false),
            settingsIsPresented: .completed(false),
            feedbackModalIsPresented: .completed(.none)
        ),
        serverRegionState: ServerRegionState(
            selectedRegion: selectedRegion,
            availableRegions: regionCodes
        )
    )
    
}

#endif
