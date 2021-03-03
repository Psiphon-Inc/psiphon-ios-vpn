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
import PsiApi
import AppStoreIAP
import PsiCashClient

var Style = AppStyle()

/// Represents UIViewController's that can be dismissed.
@objc enum DismissibleScreen: Int {
    case psiCash
}

struct AppState: Equatable {
    var vpnState = VPNState<PsiphonTPM>(.init())
    var psiCashBalance = PsiCashBalance()
    var psiCash = PsiCashState()
    var appReceipt = ReceiptState()
    var subscription = SubscriptionState()
    var subscriptionAuthState = SubscriptionAuthState()
    var iapState = IAPState()
    var products = PsiCashAppStoreProductsState()
    var pendingLandingPageOpening: Bool = false
    var internetReachability = ReachabilityState()
    var appDelegateState = AppDelegateState()
    var queuedFeedbacks: [UserFeedback] = []
    var adState = AdState()
}

extension AppState {
    
    /// True if unknown values of `AppState` have been initialized.
    var unknownValuesInitialized: Bool {
        
        // VPN Status.
        guard vpnState.value.loadState.value != .nonLoaded else {
            return false
        }
        
        // Subscription status.
        guard subscription.status != .unknown else {
            return false
        }
        
        // PsiCash lib load.
        guard psiCash.libLoaded else {
            return false
        }
        
        // Onboarding value.
        guard appDelegateState.onboardingCompleted != nil else {
            return false
        }
        
        return true
    }
    
}

struct BalanceState: Equatable {
    let pendingPsiCashRefresh: PendingPsiCashRefresh
    let psiCashBalance: PsiCashBalance
}
 
// MARK: AppAction

enum AppAction {
    case vpnStateAction(VPNStateAction<PsiphonTPM>)
    case appDelegateAction(AppDelegateAction)
    case psiCash(PsiCashAction)
    case landingPage(LandingPageAction)
    case iap(IAPAction)
    case appReceipt(ReceiptStateAction)
    case subscription(SubscriptionAction)
    case subscriptionAuthStateAction(SubscriptionAuthStateAction)
    case productRequest(ProductRequestAction)
    case reachabilityAction(ReachabilityAction)
    case feedbackAction(FeedbackAction)
    case adAction(AdAction)
}

// MARK: Environment

typealias AppEnvironment = (
    platform: Platform,
    appBundle: PsiphonBundle,
    feedbackLogger: FeedbackLogger,
    httpClient: HTTPClient,
    psiCashEffects: PsiCashEffects,
    appInfo: () -> AppInfoProvider,
    sharedDB: PsiphonDataSharedDB,
    userConfigs: UserDefaultsConfig,
    notifier: PsiApi.Notifier,
    internetReachabilityStatusSignal: SignalProducer<ReachabilityStatus, Never>,
    tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
    tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
    subscriptionStatusSignal: SignalProducer<AppStoreIAP.SubscriptionStatus, Never>,
    psiCashAuthPackageSignal: SignalProducer<PsiCashAuthPackage, Never>,
    urlHandler: URLHandler,
    paymentQueue: PaymentQueue,
    supportedAppStoreProducts: SupportedAppStoreProducts,
    objcBridgeDelegate: ObjCBridgeDelegate,
    receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate,
    paymentTransactionDelegate: PaymentTransactionDelegate,
    productRequestDelegate: ProductRequestDelegate,
    internetReachability: InternetReachability,
    internetReachabilityDelegate: StoreDelegate<ReachabilityAction>,
    vpnConnectionObserver: VPNConnectionObserver<PsiphonTPM>,
    vpnActionStore: (VPNPublicAction) -> Effect<Never>,
    psiCashStore: (PsiCashAction) -> Effect<Never>,
    appReceiptStore: (ReceiptStateAction) -> Effect<Never>,
    iapStore: (IAPAction) -> Effect<Never>,
    subscriptionStore: (SubscriptionAction) -> Effect<Never>,
    subscriptionAuthStateStore: (SubscriptionAuthStateAction) -> Effect<Never>,
    adStore: (AdAction) -> Effect<Never>,
    /// `vpnStartCondition` returns true whenever the app is in such a state as to to allow
    /// the VPN to be started. If false is returned the VPN should not be started.
    vpnStartCondition: () -> Bool,
    /// `adLoadCondition` returns true if the app is in a state where ads can be loaded.
    adLoadCondition: () -> Bool,
    getCurrentTime: () -> Date,
    compareDates: (Date, Date, Calendar.Component) -> ComparisonResult,
    getPsiphonConfig: () -> [AnyHashable: Any]?,
    getAppStateFeedbackEntry: SignalProducer<DiagnosticEntry, Never>,
    getFeedbackUpload: () -> FeedbackUploadProvider,
    adConsent: AdConsent,
    adMobInterstitialAdController: AdMobInterstitialAdController,
    adMobRewardedVideoAdController: AdMobRewardedVideoAdController,
    topMostViewController: () -> UIViewController
)

/// Creates required environment for store `Store<AppState, AppAction>`.
/// - Returns: Tuple (environment, cleanup). `cleanup` should be called
/// in `applicationWillTerminate(:_)` delegate callback.
func makeEnvironment(
    platform: Platform,
    store: Store<AppState, AppAction>,
    feedbackLogger: FeedbackLogger,
    sharedDB: PsiphonDataSharedDB,
    psiCashLib: PsiCash,
    supportedAppStoreProducts: SupportedAppStoreProducts,
    userDefaultsConfig: UserDefaultsConfig,
    objcBridgeDelegate: ObjCBridgeDelegate,
    calendar: Calendar,
    adConsent: AdConsent,
    topMostViewController: @escaping () -> UIViewController
) -> (environment: AppEnvironment, cleanup: () -> Void) {
    
    let urlSessionConfig = URLSessionConfiguration.default
    urlSessionConfig.timeoutIntervalForRequest = UrlRequestParameters.timeoutInterval
    urlSessionConfig.requestCachePolicy = UrlRequestParameters.cachePolicy
    if #available(iOS 11.0, *) {
        // waitsForConnectivity determines whether the session should wait for connectivity
        // to become available, or fail immediately.
        urlSessionConfig.waitsForConnectivity = false
    }
    let urlSession = URLSession(configuration: urlSessionConfig)
    
    let paymentTransactionDelegate = PaymentTransactionDelegate(store:
        store.projection(
            value: erase,
            action: { .iap(.transactionUpdate($0)) })
    )
    SKPaymentQueue.default().add(paymentTransactionDelegate)
    
    let adMobInterstitialAdController = AdMobInterstitialAdController(
        adUnitID: AdMobAdUnitIDs.UntunneledAdMobInterstitialAdUnitID,
        store: store.projection(
            value: erase,
            action: { .adAction($0) }
        )
    )
    
    let adMobRewardedVideoAdController = AdMobRewardedVideoAdController(
        adUnitID: AdMobAdUnitIDs.UntunneledAdMobRewardedVideoAdUnitID,
        store: store.projection(
            value: erase,
            action: { .adAction($0) }
        )
    )
    
    let reachabilityForInternetConnection = Reachability.forInternetConnection()!
    
    let environment = AppEnvironment(
        platform: platform,
        appBundle: PsiphonBundle.from(bundle: Bundle.main),
        feedbackLogger: feedbackLogger,
        httpClient: HTTPClient.default(urlSession: urlSession),
        psiCashEffects: PsiCashEffects.default(psiCash: psiCashLib, feedbackLogger: feedbackLogger),
        appInfo: { AppInfoObjC() },
        sharedDB: sharedDB,
        userConfigs: userDefaultsConfig,
        notifier: NotifierObjC(notifier:Notifier.sharedInstance()),
        internetReachabilityStatusSignal: store.$value.signalProducer.map(\.internetReachability.networkStatus),
        tunnelStatusSignal: store.$value.signalProducer
            .map(\.vpnState.value.providerVPNStatus),
        tunnelConnectionRefSignal: store.$value.signalProducer.map(\.tunnelConnection),
        subscriptionStatusSignal: store.$value.signalProducer.map(\.subscription.status),
        psiCashAuthPackageSignal: store.$value.signalProducer.map(\.psiCash.libData.authPackage),
        urlHandler: .default(),
        paymentQueue: .default,
        supportedAppStoreProducts: supportedAppStoreProducts,
        objcBridgeDelegate: objcBridgeDelegate,
        receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate(store:
            store.projection(
                value: erase,
                action: { .appReceipt($0) })
        ),
        paymentTransactionDelegate: paymentTransactionDelegate,
        productRequestDelegate: ProductRequestDelegate(store:
            store.projection(
                value: erase,
                action: { .productRequest($0) })
        ),
        internetReachability: reachabilityForInternetConnection,
        internetReachabilityDelegate: InternetReachabilityDelegate(
            reachability: reachabilityForInternetConnection,
            store: store.projection(
                value: erase,
                action: { .reachabilityAction($0) })
        ),
        vpnConnectionObserver: PsiphonTPMConnectionObserver(store:
            store.projection(value: erase,
                             action: { .vpnStateAction(.action(._vpnStatusDidChange($0))) })
        ),
        vpnActionStore: { [unowned store] (action: VPNPublicAction) -> Effect<Never> in
            .fireAndForget {
                store.send(vpnAction: action)
            }
        },
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
        },
        subscriptionAuthStateStore: { [unowned store] (action: SubscriptionAuthStateAction)
            -> Effect<Never> in
            .fireAndForget {
                store.send(.subscriptionAuthStateAction(action))
            }
        },
        adStore: { [unowned store] (action: AdAction)
            -> Effect<Never> in
            .fireAndForget {
                store.send(.adAction(action))
            }
        },
        vpnStartCondition: { [unowned store] () -> Bool in
            // VPN can be started if an ad is not being presented.
            return !store.value.adState.isPresentingAd
        },
        adLoadCondition: { [unowned store] () -> Bool in
            
            // Ads are restricted to iOS platform.
            guard case .iOS = platform.current else {
                return false
            }
            
            // Ads are restricted to non-subscribed users.
            guard case .notSubscribed = store.value.subscription.status else {
                return false
            }
            
            // Ads and Ad SDKs should not be initialized until the user
            // has finished onboarding.
            guard store.value.appDelegateState.onboardingCompleted ?? false else {
                return false
            }
            
            // Ads should not be loaded unless the app is in the foreground.
            guard store.value.appDelegateState.appLifecycle.isAppForegrounded else {
                return false
            }
            
            return true
            
        },
        getCurrentTime: { () -> Date in
            return Date()
        },
        compareDates: { date1, date2, granularity -> ComparisonResult in
            return calendar.compare(date1, to: date2, toGranularity: granularity)
        },
        getPsiphonConfig: {
            return PsiphonConfigReader.fromConfigFile()?.config
        },
        getAppStateFeedbackEntry:
            store.$value.signalProducer
            .take(first: 1)
            .map { appState -> DiagnosticEntry in
                return appState.feedbackEntry(userDefaultsConfig: userDefaultsConfig,
                                              sharedDB: sharedDB,
                                              store: store)
            },
        getFeedbackUpload: {PsiphonTunnelFeedback()},
        adConsent: adConsent,
        adMobInterstitialAdController: adMobInterstitialAdController,
        adMobRewardedVideoAdController: adMobRewardedVideoAdController,
        topMostViewController: topMostViewController
    )
    
    let cleanup = { [paymentTransactionDelegate] in
        SKPaymentQueue.default().remove(paymentTransactionDelegate)
    }
    
    return (environment: environment, cleanup: cleanup)
}

fileprivate func toPsiCashEnvironment(env: AppEnvironment) -> PsiCashEnvironment {
    PsiCashEnvironment(
        platform: env.platform,
        feedbackLogger: env.feedbackLogger,
        psiCashEffects: env.psiCashEffects,
        sharedDB: env.sharedDB,
        psiCashPersistedValues: env.userConfigs,
        notifier: env.notifier,
        vpnActionStore: env.vpnActionStore,
        objcBridgeDelegate: env.objcBridgeDelegate
    )
}

fileprivate func toLandingPageEnvironment(
    env: AppEnvironment
) -> LandingPageEnvironment {
    LandingPageEnvironment(
        feedbackLogger: env.feedbackLogger,
        sharedDB: env.sharedDB,
        urlHandler: env.urlHandler,
        psiCashEffects: env.psiCashEffects,
        psiCashAuthPackageSignal: env.psiCashAuthPackageSignal
    )
}

fileprivate func toIAPReducerEnvironment(env: AppEnvironment) -> IAPEnvironment {
    IAPEnvironment(
        feedbackLogger: env.feedbackLogger,
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        psiCashEffects: env.psiCashEffects,
        appInfo: env.appInfo,
        paymentQueue: env.paymentQueue,
        psiCashPersistedValues: env.userConfigs,
        isSupportedProduct: env.supportedAppStoreProducts.isSupportedProduct(_:),
        psiCashStore: env.psiCashStore,
        appReceiptStore: env.appReceiptStore,
        httpClient: env.httpClient,
        getCurrentTime: env.getCurrentTime
    )
}

fileprivate func toReceiptReducerEnvironment(env: AppEnvironment) -> ReceiptReducerEnvironment {
    ReceiptReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        appBundle: env.appBundle,
        iapStore: env.iapStore,
        subscriptionStore: env.subscriptionStore,
        subscriptionAuthStateStore: env.subscriptionAuthStateStore,
        receiptRefreshRequestDelegate: env.receiptRefreshRequestDelegate,
        isSupportedProduct: env.supportedAppStoreProducts.isSupportedProduct(_:),
        getCurrentTime: env.getCurrentTime,
        compareDates: env.compareDates
    )
}

fileprivate func toSubscriptionReducerEnvironment(
    env: AppEnvironment
) -> SubscriptionReducerEnvironment {
    SubscriptionReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        appReceiptStore: env.appReceiptStore,
        getCurrentTime: env.getCurrentTime,
        compareDates: env.compareDates,
        singleFireTimer: singleFireTimer
    )
}

/// - Note: This function delivers its events on the main dispatch queue.
/// - Important: Sub-millisecond precision is lost in the current implementation.
fileprivate func singleFireTimer(interval: TimeInterval,
                                 leeway: DispatchTimeInterval) -> Effect<()> {
    SignalProducer.timer(interval: DispatchTimeInterval.milliseconds(Int(interval * 1000)),
                         on: QueueScheduler.main,
                         leeway: leeway)
        .map(value: ())
        .take(first: 1)
}

fileprivate func toSubscriptionAuthStateReducerEnvironment(
    env: AppEnvironment
) -> SubscriptionAuthStateReducerEnvironment {
    SubscriptionAuthStateReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        httpClient: env.httpClient,
        httpRequestRetryCount: 5,
        httpRequestRetryInterval: DispatchTimeInterval.seconds(1),
        notifier: env.notifier,
        notifierUpdatedSubscriptionAuthsMessage: NotifierUpdatedSubscriptionAuths,
        sharedDB: SharedDBContainerObjC(sharedDB:env.sharedDB),
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        appInfo: env.appInfo,
        getCurrentTime: env.getCurrentTime,
        compareDates: env.compareDates
    )
}

fileprivate func toRequestDelegateReducerEnvironment(
    env: AppEnvironment
) -> ProductRequestEnvironment {
    ProductRequestEnvironment(
        feedbackLogger: env.feedbackLogger,
        productRequestDelegate: env.productRequestDelegate,
        supportedAppStoreProducts: env.supportedAppStoreProducts
    )
}

fileprivate func toAppDelegateReducerEnvironment(env: AppEnvironment) -> AppDelegateEnvironment {
    AppDelegateEnvironment(
        platform: env.platform,
        feedbackLogger: env.feedbackLogger,
        psiCashPersistedValues: env.userConfigs,
        sharedDB: env.sharedDB,
        psiCashEffects: env.psiCashEffects,
        paymentQueue: env.paymentQueue,
        appReceiptStore: env.appReceiptStore,
        psiCashStore: env.psiCashStore,
        adStore: env.adStore,
        paymentTransactionDelegate: env.paymentTransactionDelegate,
        userDefaultsConfig: env.userConfigs
    )
}

fileprivate func toFeedbackReducerEnvironment(env: AppEnvironment) -> FeedbackReducerEnvironment {
    FeedbackReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        getFeedbackUpload: env.getFeedbackUpload,
        internetReachabilityStatusSignal: env.internetReachabilityStatusSignal,
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        subscriptionStatusSignal: env.subscriptionStatusSignal,
        getAppStateFeedbackEntry: env.getAppStateFeedbackEntry,
        sharedDB: env.sharedDB,
        appInfo: env.appInfo,
        getPsiphonConfig: env.getPsiphonConfig,
        getCurrentTime: env.getCurrentTime
    )
}

fileprivate func toVPNReducerEnvironment(env: AppEnvironment) -> VPNReducerEnvironment<PsiphonTPM> {
    VPNReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        sharedDB: env.sharedDB,
        vpnStartCondition: env.vpnStartCondition,
        vpnConnectionObserver: env.vpnConnectionObserver,
        internetReachability: env.internetReachability
    )
}

fileprivate func toAdStateEnvironment(env: AppEnvironment) -> AdStateEnvironment {
    AdStateEnvironment(
        platform: env.platform,
        feedbackLogger: env.feedbackLogger,
        adConsent: env.adConsent,
        psiCashLib: env.psiCashEffects,
        psiCashStore: env.psiCashStore,
        tunnelStatusSignal: env.tunnelStatusSignal,
        adMobInterstitialAdController: env.adMobInterstitialAdController,
        adMobRewardedVideoAdController: env.adMobRewardedVideoAdController,
        adLoadCondition: env.adLoadCondition,
        topMostViewController: env.topMostViewController
    )
}

func makeAppReducer(
    feedbackLogger: FeedbackLogger
) -> Reducer<AppState, AppAction, AppEnvironment> {
    combine(
        pullback(makeVpnStateReducer(feedbackLogger: feedbackLogger),
                 value: \.vpnReducerState,
                 action: \.vpnStateAction,
                 environment: toVPNReducerEnvironment(env:)),
        pullback(internetReachabilityReducer,
                 value: \.internetReachability,
                 action: \.reachabilityAction,
                 environment: erase),
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
        pullback(subscriptionAuthStateReducer,
                 value: \.subscriptionAuthReducerState,
                 action: \.subscriptionAuthStateAction,
                 environment: toSubscriptionAuthStateReducerEnvironment(env:)),
        pullback(productRequestReducer,
                 value: \.products,
                 action: \.productRequest,
                 environment: toRequestDelegateReducerEnvironment(env:)),
        pullback(appDelegateReducer,
                 value: \.appDelegateReducerState,
                 action: \.appDelegateAction,
                 environment: toAppDelegateReducerEnvironment(env:)),
        pullback(feedbackReducer,
                 value: \.feedbackReducerState,
                 action: \.feedbackAction,
                 environment: toFeedbackReducerEnvironment(env:)),
        pullback(adStateReducer,
                 value: \.adReducerState,
                 action: \.adAction,
                 environment: toAdStateEnvironment(env:))
    )
}

// MARK: Store

extension Store where Value == AppState, Action == AppAction {
    
    /// Convenience send function that wraps given `VPNPublicAction` into `AppAction`.
    func send(vpnAction: VPNPublicAction) {
        self.send(.vpnStateAction(.action(.public(vpnAction))))
    }
    
}

// MARK: AppInfoProvider

struct AppInfoObjC: AppInfoProvider {
    var clientPlatform: String {
        AppInfo.clientPlatform()
    }
    var clientRegion: String {
        AppInfo.clientRegion() ?? ""
    }
    var clientVersion: String {
        AppInfo.appVersion()
    }
    var propagationChannelId: String {
        AppInfo.propagationChannelId() ?? ""
    }
    var sponsorId: String {
        AppInfo.sponsorId() ?? ""
    }
}
