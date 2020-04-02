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

#if DEBUG
var Debugging = DebugFlags()
#else
var Debugging = DebugFlags.disabled()
#endif

var Style = AppStyle()

/// A verified stricter set of `Bundle` properties.
struct PsiphonBundle {
    let bundleIdentifier: String
    let appStoreReceiptURL: URL
    
    /// Validates app's environment give the assumptions made in the app for certain invariants to hold true.
    /// - Note: Stops program execution if any of the vaidations fail.
    static func from(bundle: Bundle) -> PsiphonBundle {
        return PsiphonBundle(bundleIdentifier: bundle.bundleIdentifier!,
                             appStoreReceiptURL: bundle.appStoreReceiptURL!)
    }
}

struct DebugFlags {
    var mainThreadChecks = true
    var disableURLHandler = true
    var devServers = true
    var ignoreTunneledChecks = false
    
    var printStoreLogs = false
    var printAppState = true
    var printHttpRequests = true
    
    static func disabled() -> Self {
        return .init(mainThreadChecks: false,
                     disableURLHandler: false,
                     devServers: false,
                     ignoreTunneledChecks: false,
                     printStoreLogs: false,
                     printAppState: false,
                     printHttpRequests: false)
    }
}

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

// MARK: Environemnt

extension VPNManager {
    var tunneled: Bool {
        if Debugging.ignoreTunneledChecks { return true }
        return self.tunnelProviderStatus == .connected
    }
}

typealias AppEnvironment = (
    appBundle: PsiphonBundle,
    psiCashEffects: PsiCashEffect,
    clientMetaData: ClientMetaData,
    sharedDB: PsiphonDataSharedDB,
    userConfigs: UserDefaultsConfig,
    notifier: Notifier,
    vpnManager: VPNManager,
    vpnStatusSignal: SignalProducer<NEVPNStatus, Never>,
    psiCashAuthPackageSignal: SignalProducer<PsiCashAuthPackage, Never>,
    urlHandler: URLHandler,
    paymentQueue: PaymentQueue,
    objcBridgeDelegate: ObjCBridgeDelegate,
    receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate,
    paymentTransactionDelegate: PaymentTransactionDelegate,
    rewardedVideoAdBridgeDelegate: RewardedVideoAdBridgeDelegate,
    productRequestDelegate: ProductRequestDelegate,
    psiCashStore: (PsiCashAction) -> Effect<Never>,
    appReceiptStore: (ReceiptStateAction) -> Effect<Never>,
    iapStore: (IAPAction) -> Effect<Never>,
    subscriptionStore: (SubscriptionAction) -> Effect<Never>
)

/// Creates required environment for store `Store<AppState, AppAction>`.
/// - Returns: Tuple (environment, cleanup). `cleanup` should be called
/// in `applicationWillTerminate(:_)` delegate callback.
func makeEnvironment(
    store: Store<AppState, AppAction>,
    vpnStatus: State<NEVPNStatus>,
    psiCashLib: PsiCash,
    objcBridgeDelegate: ObjCBridgeDelegate,
    rewardedVideoAdBridgeDelegate: RewardedVideoAdBridgeDelegate
) -> (environment: AppEnvironment, cleanup: () -> Void) {
    
    let paymentTransactionDelegate = PaymentTransactionDelegate(store:
        store.projection(
            value: erase,
            action: { .iap(.transactionUpdate($0)) })
    )
    SKPaymentQueue.default().add(paymentTransactionDelegate)
    
    let environment = AppEnvironment(
        appBundle: PsiphonBundle.from(bundle: Bundle.main),
        psiCashEffects: PsiCashEffect(psiCash: psiCashLib),
        clientMetaData: ClientMetaData(),
        sharedDB: PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER),
        userConfigs: UserDefaultsConfig(),
        notifier:  Notifier.sharedInstance(),
        vpnManager:  VPNManager.sharedInstance(),
        vpnStatusSignal: vpnStatus.signalProducer,
        psiCashAuthPackageSignal: store.$value.signalProducer.map(\.psiCash.libData.authPackage),
        urlHandler: .default,
        paymentQueue: .default,
        objcBridgeDelegate: objcBridgeDelegate,
        receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate(store:
            store.projection(
                value: erase,
                action: { .appReceipt($0) })
        ),
        paymentTransactionDelegate: paymentTransactionDelegate,
        rewardedVideoAdBridgeDelegate: rewardedVideoAdBridgeDelegate,
        productRequestDelegate: ProductRequestDelegate(store:
            store.projection(
                value: erase,
                action: { .productRequest($0) })
        ),
        psiCashStore: { [unowned store] (action: PsiCashAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.psiCash(action))
            }
        },
        appReceiptStore: { [unowned store] (action: ReceiptStateAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.appReceipt(action))
            }
        },
        iapStore: { [unowned store] (action: IAPAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.iap(action))
            }
        },
        subscriptionStore: { [unowned store] (action: SubscriptionAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.subscription(action))
            }
        }
    )
    
    let cleanup = { [paymentTransactionDelegate] in
        SKPaymentQueue.default().remove(paymentTransactionDelegate)
    }
    
    return (environment: environment, cleanup: cleanup)
}

fileprivate func toPsiCashEnvironment(env: AppEnvironment) -> PsiCashEnvironment {
    PsiCashEnvironment(
        psiCashEffects: env.psiCashEffects,
        sharedDB: env.sharedDB,
        userConfigs: env.userConfigs,
        notifier: env.notifier,
        vpnManager: env.vpnManager,
        objcBridgeDelegate: env.objcBridgeDelegate,
        rewardedVideoAdBridgeDelegate: env.rewardedVideoAdBridgeDelegate
    )
}

fileprivate func toLandingPageEnvironment(env: AppEnvironment) -> LandingPageEnvironment {
    LandingPageEnvironment(
        sharedDB: env.sharedDB,
        urlHandler: env.urlHandler,
        psiCashEffects: env.psiCashEffects,
        vpnManager: env.vpnManager,
        vpnStatusSignal: env.vpnStatusSignal,
        psiCashAuthPackageSignal: env.psiCashAuthPackageSignal
    )
}

fileprivate func toIAPReducerEnvironment(env: AppEnvironment) -> IAPEnvironment {
    IAPEnvironment(
        vpnStatus: env.vpnStatusSignal,
        psiCashEffects: env.psiCashEffects,
        clientMetaData: env.clientMetaData,
        paymentQueue: env.paymentQueue,
        userConfigs: env.userConfigs,
        psiCashStore: env.psiCashStore,
        appReceiptStore: env.appReceiptStore
    )
}

fileprivate func toReceiptReducerEnvironment(env: AppEnvironment) -> ReceiptReducerEnvironment {
    ReceiptReducerEnvironment(
        appBundle: env.appBundle,
        iapStore: env.iapStore,
        subscriptionStore: env.subscriptionStore,
        receiptRefreshRequestDelegate: env.receiptRefreshRequestDelegate
    )
}

fileprivate func toSubscriptionReducerEnvironment(env: AppEnvironment) -> SubscriptionReducerEnvironment {
    SubscriptionReducerEnvironment(
        notifier: env.notifier,
        sharedDB: env.sharedDB,
        userConfigs: env.userConfigs,
        appReceiptStore: env.appReceiptStore
    )
}

fileprivate func toAppDelegateReducerEnvironment(env: AppEnvironment) -> AppDelegateEnvironment {
    AppDelegateEnvironment(
        userConfigs: env.userConfigs,
        sharedDB: env.sharedDB,
        psiCashEffects: env.psiCashEffects,
        paymentQueue: env.paymentQueue,
        appReceiptStore: env.appReceiptStore,
        psiCashStore: env.psiCashStore,
        paymentTransactionDelegate: env.paymentTransactionDelegate
    )
}

func makeAppReducer() -> Reducer<AppState, AppAction, AppEnvironment> {
    combine(
        pullback(psiCashReducer,
                 value: \.psiCashReducerState,
                 action: \.psiCash,
                 environment: toPsiCashEnvironment(env:)),
        pullback(landingPageReducer,
                 value: \.landingPageReducerState,
                 action: \.landingPage,
                 environment: toLandingPageEnvironment(env:)),
        pullback(iapReducer,
                 value: \.iapReducerState,
                 action: \.inAppPurchase,
                 environment: toIAPReducerEnvironment(env:)),
        pullback(receiptReducer,
                 value: \.appReceipt,
                 action: \.appReceipt,
                 environment: toReceiptReducerEnvironment(env:)),
        pullback(subscriptionReducer,
                 value: \.subscription,
                 action: \.subscription,
                 environment: toSubscriptionReducerEnvironment(env:)),
        pullback(productRequestReducer,
                 value: \.products,
                 action: \.productRequest,
                 environment: { $0.productRequestDelegate }),
        pullback(appDelegateReducer,
                 value: \.appDelegateReducerState,
                 action: \.appDelegateAction,
                 environment: toAppDelegateReducerEnvironment(env:))
    )
}
