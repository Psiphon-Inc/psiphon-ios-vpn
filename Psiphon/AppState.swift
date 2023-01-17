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
import enum Utilities.Unit
import PsiphonClientCommonLibrary

var Style = AppStyle()

/// Represents UIViewController's that can be dismissed.
@objc enum DismissibleScreen: Int {
    case psiCash
    case settings
}

struct AppState: Equatable {
    var vpnState = VPNState<PsiphonTPM>(.init())
    var psiCashBalance = PsiCashBalance()
    var psiCashState = PsiCashState()
    var appReceipt = ReceiptState()
    var subscription = SubscriptionState()
    var subscriptionAuthState = SubscriptionAuthState()
    var iapState = IAPState()
    var products = PsiCashAppStoreProductsState()
    var pendingLandingPageOpening: Bool = false
    var internetReachability = ReachabilityState()
    var appDelegateState = AppDelegateState()
    var queuedFeedbacks: [UserFeedback] = []
    var mainView = MainViewState()
    var serverRegionState = ServerRegionState(selectedRegion: nil)
}

// Fields of AppState that are to be included in the feedback,
// must be manually added.
extension AppState: CustomFieldFeedbackDescription {
    var feedbackFields: [String : CustomStringConvertible] {
        [
            "vpnState": String(describing: vpnState),
            "psiCashBalance": String(describing: psiCashBalance),
            "psiCashState": String(describing: psiCashState),
            "appReceipt": String(describing: appReceipt),
            "subscription": String(describing: subscription),
            "subscriptionAuthState": String(describing: subscriptionAuthState),
            "iapState": String(describing: iapState),
            "products": String(describing: products),
            "pendingLandingPageOpening": String(describing: pendingLandingPageOpening),
            "internetReachability": String(describing: internetReachability),
            "appDelegateState": String(describing: appDelegateState),
            "queuedFeedbacks": String(describing: queuedFeedbacks),
            "mainView": String(describing: mainView),
            "serverRegionState": String(describing: serverRegionState)
        ]
    }
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
        guard psiCashState.libData != nil else {
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
    let pendingPsiCashRefresh: PsiCashState.PendingRefresh
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
    case mainViewAction(MainViewAction)
    case serverRegionAction(ServerRegionAction)
}

// MARK: Environment

struct AppEnvironment {
    
    let presentedViewControllers: PresentedViewControllers
    
    let platform: Platform
    let appBundle: PsiphonBundle
    let feedbackLogger: FeedbackLogger
    let httpClient: HTTPClient
    let psiCashEffects: PsiCashEffects
    let psiCashFileStoreRoot: String?
    let appInfo: () -> AppInfoProvider
    let sharedDB: PsiphonDataSharedDB
    let sharedAuthCoreData: SharedAuthCoreData
    let userConfigs: UserDefaultsConfig
    let standardUserDefaults: UserDefaults
    let notifier: PsiApi.Notifier
    let internetReachabilityStatusSignal: SignalProducer<ReachabilityStatus, Never>
    let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    let psiCashAccountTypeSignal: SignalProducer<PsiCashAccountType?, Never>
    let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    let subscriptionStatusSignal: SignalProducer<AppStoreIAP.SubscriptionStatus, Never>
    let urlHandler: URLHandler
    let paymentQueue: AppStorePaymentQueue
    let supportedAppStoreProducts: SupportedAppStoreProducts
    let objcBridgeDelegate: ObjCBridgeDelegate
    let receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate
    let paymentTransactionDelegate: PaymentTransactionDelegate
    let productRequestDelegate: ProductRequestDelegate
    let internetReachability: InternetReachability
    let internetReachabilityDelegate: StoreDelegate<ReachabilityAction>
    let vpnConnectionObserver: VPNConnectionObserver<PsiphonTPM>
    let vpnActionStore: (VPNPublicAction) -> Effect<Never>
    let psiCashStore: (PsiCashAction) -> Effect<Never>
    let appReceiptStore: (ReceiptStateAction) -> Effect<Never>
    let iapStore: (IAPAction) -> Effect<Never>
    let subscriptionStore: (SubscriptionAction) -> Effect<Never>
    let subscriptionAuthStateStore: (SubscriptionAuthStateAction) -> Effect<Never>
    let mainViewStore: (MainViewAction) -> Effect<Never>
    let tunnelIntentStore: (TunnelStartStopIntent) -> Effect<Never>
    let serverRegionStore: (ServerRegionAction) -> Effect<Never>
    let landingPageStore: (LandingPageAction) -> Effect<Never>

    /// `vpnStartCondition` returns true whenever the app is in such a state as to to allow
    /// the VPN to be started. If false is returned the VPN should not be started
    let vpnStartCondition: () -> Bool
    
    /// `adLoadCondition` returns `nil` if the app is in a state where ads can be loaded.
    let adLoadCondition: () -> ErrorMessage?
    
    let dateCompare: DateCompare
    let addToDate: (Calendar.Component, Int, Date) -> Date?
    let rxDateScheduler: QueueScheduler
    let mainDispatcher: MainDispatcher
    let globalDispatcher: GlobalDispatcher
    let getPsiphonConfig: () -> [AnyHashable: Any]?
    let getAppStateFeedbackEntry: SignalProducer<DiagnosticEntry, Never>
    let getFeedbackUpload: () -> FeedbackUploadProvider

    let getTopActiveViewController: () -> UIViewController
    
    let reloadMainScreen: () -> Effect<Utilities.Unit>

    let makePsiCashStoreViewController: () -> PsiCashStoreViewController
    let makeSubscriptionViewController: () -> SubscriptionViewController
    let makePsiCashAccountLoginViewController: () -> PsiCashAccountLoginViewController
    let makePsiCashAccountExplainerViewController: () -> PsiCashAccountExplainerViewController
    let makeSettingsViewController: () -> NavigationController
    let makeFeedbackViewController: ([String: Any]) -> NavigationController
    
    /// Clears cache and all website data from the webview.
    let clearWebViewDataStore: () -> Effect<Never>
    
    let regionAdapter: RegionAdapter
    
    /// Reads embedded serveries entries (region codes) from file.
    let readEmbeddedServerEntries: () -> Effect<Result<Set<String>, ErrorMessage>>
    
}


/// Creates required environment for store `Store<AppState, AppAction>`.
/// - Returns: Tuple (environment, cleanup). `cleanup` should be called
/// in `applicationWillTerminate(:_)` delegate callback.
func makeEnvironment(
    platform: Platform,
    store: Store<AppState, AppAction>,
    feedbackLogger: FeedbackLogger,
    sharedDB: PsiphonDataSharedDB,
    sharedAuthCoreData: SharedAuthCoreData,
    psiCashLib: PsiCashLib,
    regionAdapter: RegionAdapter,
    embeddedServerEntriesFile: String,
    psiCashFileStoreRoot: String?,
    supportedAppStoreProducts: SupportedAppStoreProducts,
    userDefaultsConfig: UserDefaultsConfig,
    standardUserDefaults: UserDefaults,
    objcBridgeDelegate: ObjCBridgeDelegate,
    dateCompare: DateCompare,
    addToDate: @escaping (Calendar.Component, Int, Date) -> Date?,
    mainDispatcher: MainDispatcher,
    globalDispatcher: GlobalDispatcher,
    getTopActiveViewController: @escaping () -> UIViewController,
    reloadMainScreen: @escaping () -> Effect<Utilities.Unit>,
    clearWebViewDataStore: @escaping () -> Void
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
    
    let paymentTransactionDelegate = PaymentTransactionDelegate(
        store: store.projection(action: { .iap(.appStoreTransactionUpdate($0)) })
    )
    SKPaymentQueue.default().add(paymentTransactionDelegate)
    
    // RegionAdapter delegate is not expected be used.
    // Check serverRegionReducer function.
    guard regionAdapter.delegate == nil else {
        // RegionAdapter can only have one delegate.
        fatalError("Expected RegionAdapter to have a nil delegate")
    }
    
    let feedbackViewControllerDelegate = PsiphonFeedbackDelegate(store: store.stateless())
    
    let settingsViewControllerDelegate = SettingsViewControllerDelegate(
        store: store.stateless(),
        feedbackDelegate: feedbackViewControllerDelegate,
        shouldEnableSettingsLinks: true)
    
    let reachabilityForInternetConnection = Reachability.forInternetConnection()!
    
    let httpClient = HTTPClient.default(urlSession: urlSession, feedbackLogger: feedbackLogger)
    
    let tunnelStatusSignal = store.$value.signalProducer
        .map(\.vpnState.value.providerVPNStatus)
    
    // These view controller builders should take onDimissed as a param.
    let makePsiCashAccountLoginViewController: () -> PsiCashAccountLoginViewController = { [unowned store] in
        PsiCashAccountLoginViewController(
            store: store.projection(
                value: {
                    PsiCashAccountLoginViewController.ReaderState(
                        psiCashAccountType: $0.psiCashState.libData?.successToOptional()?.accountType,
                        pendingAccountLoginLogout: $0.psiCashState.pendingAccountLoginLogout
                    )
                },
                action: {
                    switch $0 {
                    case .psiCashAction(let action):
                        return .psiCash(action)
                    case .mainViewAction(let action):
                        return .mainViewAction(action)
                    }
                }
            ),
            feedbackLogger: feedbackLogger,
            tunnelStatusSignal: tunnelStatusSignal,
            tunnelConnectionRefSignal: store.$value.signalProducer.map(\.tunnelConnection),
            createNewAccountURL: psiCashLib.getUserSiteURL(.accountSignup, webview:true),
            forgotPasswordURL: psiCashLib.getUserSiteURL(.forgotAccount, webview:true),
            onDidLoad: { [unowned store] in
                store.send(.mainViewAction(.screenDidLoad(.psiCashAccountLogin)))
            },
            onDismissed: { [unowned store] in
                store.send(.mainViewAction(.screenDismissed(.psiCashAccountLogin)))
            }
        )
    }
    
    let environment = AppEnvironment(
        presentedViewControllers: PresentedViewControllers(),
        platform: platform,
        appBundle: PsiphonBundle.from(bundle: Bundle.main),
        feedbackLogger: feedbackLogger,
        httpClient: httpClient,
        psiCashEffects: PsiCashEffects(psiCashLib: psiCashLib,
                                       httpClient: httpClient,
                                       globalDispatcher: globalDispatcher,
                                       getCurrentTime: dateCompare.getCurrentTime,
                                       feedbackLogger: feedbackLogger),
        psiCashFileStoreRoot: psiCashFileStoreRoot,
        appInfo: { AppInfoObjC() },
        sharedDB: sharedDB,
        sharedAuthCoreData: sharedAuthCoreData,
        userConfigs: userDefaultsConfig,
        standardUserDefaults: standardUserDefaults,
        notifier: NotifierObjC(notifier:Notifier.sharedInstance()),
        internetReachabilityStatusSignal: store.$value.signalProducer.map(\.internetReachability.networkStatus),
        tunnelStatusSignal: tunnelStatusSignal,
        psiCashAccountTypeSignal: store.$value.signalProducer.map {
            $0.psiCashState.libData?.successToOptional()?.accountType
        },
        tunnelConnectionRefSignal: store.$value.signalProducer.map(\.tunnelConnection),
        subscriptionStatusSignal: store.$value.signalProducer.map(\.subscription.status),
        urlHandler: .default(),
        paymentQueue: .default,
        supportedAppStoreProducts: supportedAppStoreProducts,
        objcBridgeDelegate: objcBridgeDelegate,
        receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate(store:
            store.projection(action: { .appReceipt($0) })
        ),
        paymentTransactionDelegate: paymentTransactionDelegate,
        productRequestDelegate: ProductRequestDelegate(store:
            store.projection(action: { .productRequest($0) })
        ),
        internetReachability: reachabilityForInternetConnection,
        internetReachabilityDelegate: InternetReachabilityDelegate(
            reachability: reachabilityForInternetConnection,
            store: store.projection(action: { .reachabilityAction($0) })
        ),
        vpnConnectionObserver: PsiphonTPMConnectionObserver(store:
            store.projection(action: { .vpnStateAction(.action(._vpnStatusDidChange($0))) })
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
        mainViewStore: { [unowned store] (action: MainViewAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.mainViewAction(action))
            }
        },
        tunnelIntentStore: { [unowned store] (action: TunnelStartStopIntent) -> Effect<Never> in
            .fireAndForget {
                store.send(vpnAction: .tunnelStateIntent(intent: action, reason: .userInitiated))
            }
        },
        serverRegionStore: { [unowned store] (action: ServerRegionAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.serverRegionAction(action))
            }
        },
        landingPageStore: { [unowned store] (action: LandingPageAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.landingPage(action))
            }
        },
        vpnStartCondition: { () -> Bool in
            // Retruns true if the VPN can be started given the current state of the app.
            // Legacy: It was used to disallow starting VPN if an interstitial ad is presented.
            return true
        },
        adLoadCondition: { [unowned store] () -> ErrorMessage? in
            
            // Ads are restricted to iOS platform.
            guard case .iOS = platform.current else {
                return ErrorMessage("current platform is '\(platform.current)'")
            }
            
            // Ads are restricted to non-subscribed users.
            guard case .notSubscribed = store.value.subscription.status else {
                return ErrorMessage("subscription status is '\(store.value.subscription.status)'")
            }
            
            // Ads and Ad SDKs should not be initialized until the user
            // has finished onboarding.
            guard store.value.appDelegateState.onboardingCompleted ?? false else {
                return ErrorMessage("onboarding not completed")
            }
            
            // Ads should not be loaded unless the app is in the foreground.
            guard store.value.appDelegateState.appLifecycle.isAppForegrounded else {
                return ErrorMessage("""
                    app is not foregrounded: '\(store.value.appDelegateState.appLifecycle)'
                    """)
            }
            
            return .none
            
        },
        dateCompare: dateCompare,
        addToDate: addToDate,
        rxDateScheduler: QueueScheduler.main,
        mainDispatcher: mainDispatcher,
        globalDispatcher: globalDispatcher,
        getPsiphonConfig: {
            return PsiphonConfigReader.load()?.config
        },
        getAppStateFeedbackEntry:
            store.$value.signalProducer
            .take(first: 1)
            .map { appState -> DiagnosticEntry in
                return appState.feedbackEntry(userDefaultsConfig: userDefaultsConfig,
                                              sharedDB: sharedDB,
                                              store: store,
                                              psiCashLib: psiCashLib)
            },
        getFeedbackUpload: { PsiphonTunnelFeedback() },
        getTopActiveViewController: getTopActiveViewController,
        reloadMainScreen: reloadMainScreen,
        makePsiCashStoreViewController: { [unowned store] in
            PsiCashStoreViewController(
                platform: platform,
                locale: userDefaultsConfig.localeForAppLanguage,
                store: store.projection(
                    value: { $0.psiCashStoreViewControllerReaderState },
                    action: {
                        switch $0 {
                        case let .mainViewAction(action):
                            return .mainViewAction(action)
                        case let .psiCashAction(action):
                            return .psiCash(action)
                        }
                    }),
                iapStore: store.projection(action: { .iap($0) }),
                productRequestStore: store.projection(action: { .productRequest($0) } ),
                appStoreReceiptStore: store.projection(action: { .appReceipt($0) } ),
                tunnelConnectedSignal: store.$value.signalProducer
                    .map(\.vpnState.value.providerVPNStatus.tunneled),
                dateCompare: dateCompare,
                feedbackLogger: feedbackLogger,
                tunnelConnectionRefSignal: store.$value.signalProducer.map(\.tunnelConnection),
                objCBridgeDelegate: objcBridgeDelegate,
                onDidLoad: { [unowned store] in
                    store.send(.mainViewAction(.screenDidLoad(.psiCashStore)))
                },
                onDismissed: { [unowned store] in
                    store.send(.mainViewAction(.screenDismissed(.psiCashStore)))
                }
            )
        },
        makeSubscriptionViewController: {
            SubscriptionViewController()
        },
        makePsiCashAccountLoginViewController: {
            makePsiCashAccountLoginViewController()
        },
        makePsiCashAccountExplainerViewController: {
            PsiCashAccountExplainerViewController(
                makePsiCashAccountLoginViewController: makePsiCashAccountLoginViewController,
                createNewAccountURL: psiCashLib.getUserSiteURL(.accountSignup, webview: true),
                learnMorePsiCashAccountURL: PsiCashHardCodedValues.accountsLearnMoreURL,
                psiCashStore: store.projection(action: { .psiCash($0) }),
                tunnelStatusSignal: tunnelStatusSignal,
                tunnelConnectionRefSignal: store.$value.signalProducer.map(\.tunnelConnection),
                feedbackLogger: feedbackLogger
            )
        },
        makeSettingsViewController: {
            let vc = SettingsViewController_Swift()
            vc.delegate = vc;
            vc.showCreditsFooter = false;
            vc.showDoneButton = true;
            vc.neverShowPrivacySettings = true;
            vc.settingsDelegate = settingsViewControllerDelegate
            vc.preferencesSnapshot = UserDefaults.standard.dictionaryRepresentation()

            let nav = NavigationController(rootViewController: vc)
            // The default navigation controller in the iOS 13 SDK is not fullscreen and can be
            // dismissed by swiping it away.
            //
            // PsiphonSettingsViewController depends on being dismissed with the "done" button, which
            // is hooked into the InAppSettingsKit lifecycle. Swiping away the settings menu bypasses
            // this and results in the VPN not being restarted if: a new region was selected, the
            // disable timeouts settings was changed, etc. The solution is to force fullscreen
            // presentation until the settings menu can be refactored.
            nav.modalPresentationStyle = .fullScreen

            return nav
        },
        makeFeedbackViewController: { (associatedData: [String: Any]) in

            // TODO: This is a hack. Ideally IASK should be retired.
            // FeedbackViewController is implemeneted as part of InAppSettingsKit.
            // Since it does not store any user configs, we can present it
            // safely from here without providing the  IASKSettingsStore object.
            let commonLibBundle = PsiphonClientCommonLibraryHelpers.commonLibraryBundle()
            let vc = FeedbackViewController()
            vc.associatedData = associatedData
            vc.delegate = vc
            vc.feedbackDelegate = feedbackViewControllerDelegate
            vc.bundle = commonLibBundle
            vc.file = "Feedback"
            vc.settingsStore = nil
            vc.showDoneButton = false
            vc.showCreditsFooter = false
            // Default title value is "Settings"
            vc.title = UserStrings.Feedback_title()
            
            let nav = NavigationController(rootViewController: vc)
            return nav
            
        },
        clearWebViewDataStore: {
            .fireAndForget {
                clearWebViewDataStore()
            }
        },
        regionAdapter: regionAdapter,
        readEmbeddedServerEntries: { () -> Effect<Result<Set<String>, ErrorMessage>> in
            
            // Reads embedded server entries.
            Effect.deferred {
                
                var error: NSError? = nil
                let embeddedRegions = EmbeddedServerEntries.egressRegions(
                    fromFile: embeddedServerEntriesFile, error: &error)
                
                if let error = error {
                    let systemError = SystemError<Int>.make(error)
                    return .failure(ErrorMessage("\(systemError)"))
                }
                
                guard !embeddedRegions.isEmpty else {
                    return .failure(ErrorMessage("No embedded egress regions found"))
                }
                
                return .success(embeddedRegions as! Set<String>)
                
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
        platform: env.platform,
        feedbackLogger: env.feedbackLogger,
        psiCashFileStoreRoot: env.psiCashFileStoreRoot,
        psiCashEffects: env.psiCashEffects,
        sharedAuthCoreData: env.sharedAuthCoreData,
        psiCashPersistedValues: env.userConfigs,
        notifier: env.notifier,
        notifierUpdatedAuthorizationsMessage: NotifierUpdatedAuthorizations,
        vpnActionStore: env.vpnActionStore,
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        objcBridgeDelegate: env.objcBridgeDelegate,
        metadata: { ClientMetaData(env.appInfo()) },
        getCurrentTime: env.dateCompare.getCurrentTime,
        psiCashLegacyDataStore: env.standardUserDefaults,
        userConfigs: env.userConfigs,
        mainDispatcher: env.mainDispatcher,
        clearWebViewDataStore: env.clearWebViewDataStore
    )
}

fileprivate func toLandingPageEnvironment(env: AppEnvironment) -> LandingPageEnvironment {
    LandingPageEnvironment(
        feedbackLogger: env.feedbackLogger,
        sharedDB: env.sharedDB,
        urlHandler: env.urlHandler,
        psiCashEffects: env.psiCashEffects,
        psiCashAccountTypeSignal: env.psiCashAccountTypeSignal,
        dateCompare: env.dateCompare,
        tunnelStatusSignal: env.tunnelStatusSignal,
        mainViewStore: env.mainViewStore,
        mainDispatcher: env.mainDispatcher
    )
}

fileprivate func toIAPReducerEnvironment(env: AppEnvironment) -> IAPEnvironment {
    IAPEnvironment(
        feedbackLogger: env.feedbackLogger,
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        psiCashEffects: env.psiCashEffects,
        clientMetaData: { ClientMetaData(env.appInfo()) },
        paymentQueue: env.paymentQueue,
        psiCashPersistedValues: env.userConfigs,
        isSupportedProduct: env.supportedAppStoreProducts.isSupportedProduct(_:),
        psiCashStore: env.psiCashStore,
        appReceiptStore: env.appReceiptStore,
        httpClient: env.httpClient,
        getCurrentTime: env.dateCompare.getCurrentTime
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
        dateCompare: env.dateCompare
    )
}

fileprivate func toSubscriptionReducerEnvironment(
    env: AppEnvironment
) -> SubscriptionReducerEnvironment {
    SubscriptionReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        appReceiptStore: env.appReceiptStore,
        dateCompare: env.dateCompare,
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
        notifierUpdatedAuthorizationsMessage: NotifierUpdatedAuthorizations,
        sharedAuthCoreData: env.sharedAuthCoreData,
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        clientMetaData: { ClientMetaData(env.appInfo()) },
        dateCompare: env.dateCompare,
        mainDispatcher: env.mainDispatcher
    )
}

fileprivate func toRequestDelegateReducerEnvironment(
    env: AppEnvironment
) -> ProductRequestEnvironment {
    ProductRequestEnvironment(
        feedbackLogger: env.feedbackLogger,
        productRequestDelegate: env.productRequestDelegate,
        supportedAppStoreProducts: env.supportedAppStoreProducts,
        getCurrentLocale: { env.userConfigs.localeForAppLanguage }
    )
}

fileprivate func toAppDelegateReducerEnvironment(env: AppEnvironment) -> AppDelegateEnvironment {
    AppDelegateEnvironment(
        platform: env.platform,
        feedbackLogger: env.feedbackLogger,
        sharedDB: env.sharedDB,
        psiCashEffects: env.psiCashEffects,
        paymentQueue: env.paymentQueue,
        mainViewStore: env.mainViewStore,
        appReceiptStore: env.appReceiptStore,
        serverRegionStore: env.serverRegionStore,
        landingPageStore: env.landingPageStore,
        paymentTransactionDelegate: env.paymentTransactionDelegate,
        mainDispatcher: env.mainDispatcher,
        getCurrentTime: env.dateCompare.getCurrentTime,
        dateCompare: env.dateCompare,
        userDefaultsConfig: env.userConfigs,
        tunnelStatusSignal: env.tunnelStatusSignal
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
        userConfigs: env.userConfigs,
        appInfo: env.appInfo,
        getPsiphonConfig: env.getPsiphonConfig,
        getCurrentTime: env.dateCompare.getCurrentTime,
        mainViewStore: env.mainViewStore
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

func toMainViewReducerEnvironment(env: AppEnvironment) -> MainViewEnvironment {
    MainViewEnvironment(
        presentedViewControllers: env.presentedViewControllers,
        vpnActionStore: env.vpnActionStore,
        userConfigs: env.userConfigs,
        sharedDB: env.sharedDB,
        psiCashStore: env.psiCashStore,
        psiCashStoreViewEnvironment: PsiCashStoreViewEnvironment(
            feedbackLogger: env.feedbackLogger,
            iapStore: env.iapStore,
            mainViewStore: env.mainViewStore,
            getTopActiveViewController: env.getTopActiveViewController,
            dateCompare: env.dateCompare
        ),
        getTopActiveViewController: env.getTopActiveViewController,
        feedbackLogger: env.feedbackLogger,
        rxDateScheduler: env.rxDateScheduler,
        makeSubscriptionViewController: env.makeSubscriptionViewController,
        dateCompare: env.dateCompare,
        addToDate: env.addToDate,
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        psiCashEffects: env.psiCashEffects,
        tunnelIntentStore: env.tunnelIntentStore,
        serverRegionStore: env.serverRegionStore,
        reloadMainScreen: env.reloadMainScreen,
        makePsiCashStoreViewController: env.makePsiCashStoreViewController,
        makePsiCashAccountExplainerViewController: env.makePsiCashAccountExplainerViewController,
        makeSettingsViewController: env.makeSettingsViewController,
        makeFeedbackViewController: env.makeFeedbackViewController
    )
}

fileprivate func toSelectedRegionReducerEnvironment(
    env: AppEnvironment
) -> ServerRegionEnvironment {
    
    ServerRegionEnvironment(
        regionAdapter: env.regionAdapter,
        sharedDB: env.sharedDB,
        readEmbeddedServerEntries: env.readEmbeddedServerEntries,
        tunnelIntentStore: env.tunnelIntentStore,
        feedbackLogger: env.feedbackLogger
    )
    
}

func makeAppReducer(
    feedbackLogger: FeedbackLogger
) -> Reducer<AppState, AppAction, AppEnvironment> {
    Reducer.combine(
        vpnStateReducer(feedbackLogger: feedbackLogger).pullback(
                 value: \.vpnReducerState,
                 action: \.vpnStateAction,
                 environment: toVPNReducerEnvironment(env:)),
        internetReachabilityReducer.pullback(
                 value: \.internetReachability,
                 action: \.reachabilityAction,
                 environment: erase),
        psiCashReducer.pullback(
                 value: \.psiCashReducerState,
                 action: \.psiCash,
                 environment: toPsiCashEnvironment(env:)),
        landingPageReducer.pullback(
                 value: \.landingPageReducerState,
                 action: \.landingPage,
                 environment: toLandingPageEnvironment(env:)),
        iapReducer.pullback(
                 value: \.iapReducerState,
                 action: \.inAppPurchase,
                 environment: toIAPReducerEnvironment(env:)),
        receiptReducer.pullback(
                 value: \.appReceipt,
                 action: \.appReceipt,
                 environment: toReceiptReducerEnvironment(env:)),
        subscriptionTimerReducer.pullback(
                 value: \.subscription,
                 action: \.subscription,
                 environment: toSubscriptionReducerEnvironment(env:)),
        subscriptionAuthStateReducer.pullback(
                 value: \.subscriptionAuthState,
                 action: \.subscriptionAuthStateAction,
                 environment: toSubscriptionAuthStateReducerEnvironment(env:)),
        productRequestReducer.pullback(
                 value: \.products,
                 action: \.productRequest,
                 environment: toRequestDelegateReducerEnvironment(env:)),
        appDelegateReducer.pullback(
                 value: \.appDelegateReducerState,
                 action: \.appDelegateAction,
                 environment: toAppDelegateReducerEnvironment(env:)),
        feedbackReducer.pullback(
                 value: \.feedbackReducerState,
                 action: \.feedbackAction,
                 environment: toFeedbackReducerEnvironment(env:)),
        mainViewReducer.pullback(
            value: \.mainViewReducerState,
            action: \.mainViewAction,
            environment: toMainViewReducerEnvironment(env:)),
        serverRegionReducer.pullback(
            value: \.serverRegionState,
            action: \.serverRegionAction,
            environment: toSelectedRegionReducerEnvironment(env:))
    )
}

// MARK: PresentedViewControllers

/// Holds references to presented view controllers.
// TODO: Not all view controllers are stored here, this should replace all uses of `presentIfTypeNotPresent` and potentially `traversePresentingStackFor` APIs.
final class PresentedViewControllers {
    
    weak var disallowedTraffic: UIAlertController?
    
    weak var psiCashAccountManagement: PsiNavigationController?
    
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
