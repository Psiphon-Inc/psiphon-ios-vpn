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
import Promises
import StoreKit
import NetworkExtension
import Utilities
import PsiApi
import AppStoreIAP
import PsiCashClient
import PsiphonClientCommonLibrary
import WebKit

enum AppLifecycle: Equatable {
    case inited
    case didFinishLaunching
    case didBecomeActive
    case willResignActive
    case didEnterBackground
    case willEnterForeground
}

extension AppLifecycle {
    
    /// Returns true if the app is foregrounded, or will be foregrounded soon.
    var isAppForegrounded: Bool {
        switch self {
        case .inited, .didFinishLaunching, .didBecomeActive, .willEnterForeground:
            return true
        case .willResignActive, .didEnterBackground:
            return false
        }
    }
    
}

enum AppDelegateAction {
    case appLifecycleEvent(AppLifecycle)
    case checkForDisallowedTrafficAlertNotification
    case onboardingCompleted
}

struct AppDelegateReducerState: Equatable {
    var appDelegateState: AppDelegateState
    let subscriptionState: SubscriptionState
}

struct AppDelegateState: Equatable {
    
    var appLifecycle: AppLifecycle = .inited
        
    /// Represents whether a disallowed traffic alert has been requested to be presented,
    /// but has not yet been presented.
    var pendingPresentingDisallowedTrafficAlert: Bool = false
    
    /// Represents whether or not the user has completed the onboarding.
    /// `nil` is the case where the onboarding status is not known yet.
    var onboardingCompleted: Bool? = .none
    
}

struct AppDelegateEnvironment {
    let platform: Platform
    let feedbackLogger: FeedbackLogger
    let sharedDB: PsiphonDataSharedDB
    let psiCashEffects: PsiCashEffects
    let paymentQueue: PaymentQueue
    let mainViewStore: (MainViewAction) -> Effect<Never>
    let appReceiptStore: (ReceiptStateAction) -> Effect<Never>
    let paymentTransactionDelegate: PaymentTransactionDelegate
    let mainDispatcher: MainDispatcher
    let getCurrentTime: () -> Date
    let userDefaultsConfig: UserDefaultsConfig
}

let appDelegateReducer = Reducer<AppDelegateReducerState,
                                 AppDelegateAction,
                                 AppDelegateEnvironment> {
    state, action, environment in
    
    switch action {
    
    case .appLifecycleEvent(let lifecycle):
        
        state.appDelegateState.appLifecycle = lifecycle
        
        switch lifecycle {
        
        case .didFinishLaunching:
            // Determines whether onboarding is complete.
            let stagesNotCompleted = OnboardingStage.findStagesNotCompleted(
                completedStages: environment.userDefaultsConfig.onboardingStagesCompletedTyped)
            
            state.appDelegateState.onboardingCompleted = stagesNotCompleted.isEmpty
            
            return [
                environment.paymentQueue.addObserver(environment.paymentTransactionDelegate).mapNever(),
                environment.appReceiptStore(.readLocalReceiptFile).mapNever()
            ]
        
        case .didBecomeActive:
            return [
                Effect(value: .checkForDisallowedTrafficAlertNotification)
            ]
            
        default:
            return []
            
        }
        
    case .checkForDisallowedTrafficAlertNotification:

        let lastReadSeq = environment.sharedDB
            .getContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum()
        
        // Last sequence number written by the extension
        let writeSeq = environment.sharedDB.getDisallowedTrafficAlertWriteSequenceNum()
        
        guard writeSeq > lastReadSeq else {
            return []
        }
        
        // TODO: The `date` of this event should really be the same as the last seq number read.
        // In the implementation below two AlertEvents for the same seq number, are not equal.
        let alertEvent = AlertEvent(.disallowedTrafficAlert,
                                    date: environment.getCurrentTime())

        var effects = [Effect<AppDelegateAction>]()

        // Updates disallowed traffic alert read seq number.
        effects += .fireAndForget {
            environment.sharedDB.setContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum(
                environment.sharedDB.getDisallowedTrafficAlertWriteSequenceNum())
        }

        // Presents disallowed traffic alert only if the user is not subscribed.
        if case .subscribed(_) = state.subscriptionState.status {
            effects += environment.feedbackLogger
                .log(.info, "Disallowed traffic alert not presented.")
                .mapNever()
        } else {
            effects += [
                environment.feedbackLogger.log(.info, "Presenting disallowed traffic alert")
                    .mapNever(),
                environment.mainViewStore(.presentAlert(alertEvent)).mapNever(),
            ]
        }

        return effects
        
    case .onboardingCompleted:
        
        state.appDelegateState.onboardingCompleted = true
        
        return [
            .fireAndForget {
                environment.userDefaultsConfig.onboardingStagesCompleted =
                    OnboardingStage.stagesToComplete.map(\.rawValue)
            }
        ]
        
    }
    
}

// MARK: SwiftAppDelegate
@objc final class SwiftDelegate: NSObject {
    
    static let instance = SwiftDelegate()

    private var platform: Platform!
    private var deepLinkingNavigator = DeepLinkingNavigator()
    private let sharedDB = PsiphonDataSharedDB(forAppGroupIdentifier: PsiphonAppGroupIdentifier)
    let feedbackLogger = FeedbackLogger(PsiphonRotatingFileFeedbackLogHandler())
    private let supportedProducts =
        SupportedAppStoreProducts.fromPlists(types: [.subscription, .psiCash])
    private let userDefaultsConfig = UserDefaultsConfig()
    private let appUpgrade = AppUpgrade()
    private let dateCompare: DateCompare
    private let appSupportFileStore: ApplicationSupportFileStore
    private let sharedAuthCoreData: SharedAuthCoreData
    
    private var (lifetime, token) = Lifetime.make()
    private var objcBridge: ObjCBridgeDelegate!
    private var store: Store<AppState, AppAction>!
    private var psiCashLib: PsiCashLib
    private var environmentCleanup: (() -> Void)?

    // NSNotification observers
    private var appLangChagneObserver: NSObjectProtocol?
    
    private override init() {

        deepLinkingNavigator = DeepLinkingNavigator()

        dateCompare = DateCompare(
            getCurrentTime: { Date () },
            compareDates: { Calendar.current.compare($0, to: $1, toGranularity: $2) })
        
        appSupportFileStore = ApplicationSupportFileStore(fileManager: FileManager.default)
        
        sharedAuthCoreData = SharedCoreData_Impl()
        
        platform = Platform(ProcessInfo.processInfo)
        
        psiCashLib = PsiCashLib(feedbackLogger: self.feedbackLogger, platform: platform)
        
    }
    
    // Should be called early in the application lifecycle.
    @objc static func setupDebugFlags() {
        #if DEBUG
        Debugging = DebugFlags(buildConfig: .debug)
        #elseif DEV_RELEASE
        Debugging = DebugFlags(
            buildConfig: .devRelease,
            devServers: true
        )
        #else
        Debugging = DebugFlags.disabled(buildConfig: .release)
        #endif
    }
    
    func applicationDidBecomeActive() {
        
        self.store.send(.appDelegateAction(.appLifecycleEvent(.didBecomeActive)))
        self.store.send(.mainViewAction(.applicationDidBecomeActive))
        
    }
    
    func applicationWillEnterForeground() {
                
        // Updates appForegroundState shared with the extension before
        // syncing with it through the `.syncWithProvider` message.
        self.sharedDB.setAppForegroundState(true)
        
        self.store.send(.appDelegateAction(.appLifecycleEvent(.willEnterForeground)))
        self.store.send(vpnAction: .syncWithProvider(reason: .appEnteredForeground))
        self.store.send(.psiCash(.refreshPsiCashState()))
        
    }
    
    func applicationDidEnterBackground() {
        
        self.store.send(.appDelegateAction(.appLifecycleEvent(.didEnterBackground)))
        self.sharedDB.setAppForegroundState(false)
        
        Notifier.sharedInstance().post(NotifierAppEnteredBackground)
        
    }
    
    func applicationWillResignActive() {
        
        self.store.send(.appDelegateAction(.appLifecycleEvent(.willResignActive)))
        
    }

}

// MARK: Bridge API

extension SwiftDelegate {
    
    func installVPNConfig() -> Promise<VPNConfigInstallResult> {
        let promise = Promise<VPNConfigInstallResult>.pending()
        
        self.store.$value.signalProducer
            .map(\.vpnState.value.loadState.value)
            .skipRepeats()
            .scan(IndexedPsiphonTPMLoadState(index: 0, value: .nonLoaded))
            { (previous, tpmLoadState) -> IndexedPsiphonTPMLoadState in
                // Indexes `tpmLoadState` emitted items, starting from 0.
                return IndexedPsiphonTPMLoadState(index: previous.index + 1, value: tpmLoadState)
            }.flatMap(.latest) { [unowned self] indexed
                -> SignalProducer<IndexedPsiphonTPMLoadState, Never> in
                
                // Index 1 represents the value of ProviderManagerLoadState before
                // `.reinstallVPNConfig` action is sent.
                
                switch indexed.index {
                case 0:
                    self.feedbackLogger.fatalError("Unexpected index 0")
                    return .empty
                case 1:
                    switch indexed.value {
                    case .nonLoaded:
                        return Effect.never
                    case .noneStored, .loaded(_), .error(_):
                        return Effect(value: indexed)
                    }
                default:
                    switch indexed.value {
                    case .nonLoaded,.noneStored:
                        return Effect.never
                    case .loaded(_), .error(_):
                        return Effect(value: indexed)
                    }
                }
            }
            .take(first: 2)
            .startWithValues { [promise, unowned self] indexed in
                switch indexed.index {
                case 0:
                    self.feedbackLogger.fatalError("Unexpected index 0")
                    return
                case 1:
                    self.store.send(vpnAction: .reinstallVPNConfig)
                default:
                    switch indexed.value {
                    case .nonLoaded, .noneStored:
                        self.feedbackLogger.fatalError("Unexpected value '\(indexed.value)'")
                        return
                    case .loaded(_):
                        promise.fulfill(.installedSuccessfully)
                    case .error(let errorEvent):
                        if case .failedConfigLoadSave(let error) = errorEvent.error {
                            if error.configurationReadWriteFailedPermissionDenied {
                                promise.fulfill(.permissionDenied)
                            } else {
                                promise.fulfill(.otherError)
                            }
                        }
                    }
                }
            }
        
        return promise
    }
    
}

extension SwiftDelegate: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        self.feedbackLogger.immediate(.info, """
            received user notification: identifier: '\(response.notification.request.identifier)'
            """)
        completionHandler()
    }
    
}

// API exposed to ObjC.
extension SwiftDelegate: SwiftBridgeDelegate {
    
    @objc static var bridge: SwiftBridgeDelegate {
        return SwiftDelegate.instance
    }
    
    @objc func applicationWillFinishLaunching(
        _ application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey : Any]?,
        objcBridge: ObjCBridgeDelegate
    ) -> Bool {

        print("Build Configuration: '\(String(describing: Debugging.buildConfig))'")

        self.objcBridge = objcBridge
        
        // Updates appForegroundState that is shared with the extension.
        self.sharedDB.setAppForegroundState(true)
        
        self.appUpgrade.checkForUpgrade(userDefaultsConfig: self.userDefaultsConfig,
                                        appInfo: AppInfoObjC(),
                                        feedbackLogger: self.feedbackLogger)
        
        if appUpgrade.firstRunOfVersion == true {
            self.objcBridge.updateAvailableEgressRegionsOnFirstRunOfAppVersion()
        }
        
        UNUserNotificationCenter.current().delegate = self
        
        return true
    }
    
    @objc func applicationDidFinishLaunching(
        _ application: UIApplication
    ) {
        self.feedbackLogger.immediate(.info, "applicationDidFinishLaunching")
        
        // Logs any filesystem errors stored.
        if let error = appSupportFileStore.filesystemError {
            self.feedbackLogger.immediate(.error, "\(error)")
        }
        
        let mainDispatcher = MainDispatcher()
        let globalDispatcher = GlobalDispatcher(qos: .default, name: "globalDispatcher")
        
        // On Mac the iOS AppDelegate callbacks are not called when the app's window
        // loses focus. Once the app is opened "applicationDidBecomeActive" is called once,
        // unless the application is hidden and reopened again.
        //
        // The current strategy is to call "applicationWillEnterForeground", "applicationDidBecomeActive",
        // "applicationWillResignActive", "applicationDidEnterBackground" only based on
        // "NSWindowDidBecomeMainNotification" and "NSWindowDidResignMainNotification" notifications.
        
        if case .iOSAppOnMac = platform.current {
            
            NotificationCenter.default.addObserver(forName: .init("NSWindowDidBecomeMainNotification"), object: nil, queue: nil) { notification in
                
                self.applicationWillEnterForeground()
                self.applicationDidBecomeActive()
                
            }
            
            NotificationCenter.default.addObserver(forName: .init("NSWindowDidResignMainNotification"), object: nil, queue: nil) { notification in
                
                self.applicationWillResignActive()
                self.applicationDidEnterBackground()
                
            }
            
        }
        self.store = Store(
            initialValue: AppState(),
            reducer: makeAppReducer(feedbackLogger: self.feedbackLogger),
            dispatcher: mainDispatcher,
            environment: { [unowned self] store in
                let (environment, cleanup) = makeEnvironment(
                    platform: platform,
                    store: store,
                    feedbackLogger: self.feedbackLogger,
                    sharedDB: self.sharedDB,
                    sharedAuthCoreData: SharedCoreData_Impl(),
                    psiCashLib: self.psiCashLib,
                    psiCashFileStoreRoot: self.appSupportFileStore.psiCashFileStoreRootPath,
                    supportedAppStoreProducts: self.supportedProducts,
                    userDefaultsConfig: self.userDefaultsConfig,
                    standardUserDefaults: UserDefaults.standard,
                    objcBridgeDelegate: objcBridge,
                    dateCompare: self.dateCompare,
                    addToDate: { calendarComponent, value, date -> Date? in
                        Calendar.current.date(byAdding: calendarComponent, value: value, to: date)
                    },
                    mainDispatcher: mainDispatcher,
                    globalDispatcher: globalDispatcher,
                    getTopActiveViewController: self.getTopActiveViewController,
                    clearWebViewDataStore: {
                        WKWebView.clearWebviewDataStore()
                    }
                )
                self.environmentCleanup = cleanup
                return environment
            })
        
        self.store.send(.appDelegateAction(.appLifecycleEvent(.didFinishLaunching)))
        self.store.send(vpnAction: .appLaunched)
        self.store.send(.psiCash(.initialize))

        // Registers accepted deep linking URLs.
        deepLinkingNavigator.register(urls: [ PsiphonDeepLinking.legacyBuyPsiCashDeepLink,
                                             PsiphonDeepLinking.buyPsiCashDeepLink ]) { [unowned self] in
            self.store.send(.mainViewAction(.presentPsiCashScreen(initialTab: .addPsiCash)))
            return true
        }
        deepLinkingNavigator.register(urls: [ PsiphonDeepLinking.legacySpeedBoostDeepLink,
                                              PsiphonDeepLinking.speedBoostDeepLink ]) { [unowned self] in
            self.store.send(.mainViewAction(.presentPsiCashScreen(initialTab: .speedBoost)))
            return true
        }
        
        // Note that settings can also change outside of IASK menu,
        // such as language selection in onboarding.
        appLangChagneObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(kIASKAppSettingChanged),
            object: nil,
            queue: .main
        ) { [unowned self] note in
            
            let fieldName = note.userInfo?.keys.first as? String?
            
            if fieldName == PsiphonCommonLibConstants.kAppLanguage {
                let currentLocale = self.userDefaultsConfig.localeForAppLanguage
                self.store.send(.psiCash(.setLocale(currentLocale)))
            }
            
        }
        
        // Observes VPN connected state, and sends actions that need to be performed.
        self.lifetime += self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus)
            .skipRepeats()
            .filter { $0 == .connected }
            .startWithValues { _ in
                
                // PsiCash RefreshState
                self.store.send(.psiCash(.refreshPsiCashState()))
                
                // Validity of subscription authorization is determined by Psiphon servers
                // when the VPN connects.
                // Performs a local receipt refersh in case there is a new
                // that can be retrieved. (e.g. server authorization rekey.)
                self.store.send(.appReceipt(.readLocalReceiptFile))
                
            }
        
        // Forwards `SubscriptionStatus` updates to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.subscription.status)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] in
                objcBridge!.onSubscriptionStatus(BridgedUserSubscription.from(state: $0))
            }
        
        // Forwards subscription auth status to ObjCBridgeDelegate.
        self.lifetime += SignalProducer.combineLatest(
            self.store.$value.signalProducer.map(\.subscriptionAuthState).skipRepeats(),
            self.store.$value.signalProducer.map(\.subscription.status).skipRepeats(),
            self.store.$value.signalProducer
                .map(\.vpnState.value.providerVPNStatus.tunneled).skipRepeats()
        ).map {
            SubscriptionBarView.SubscriptionBarState.make(
                subscriptionAuthState: $0.0, subscriptionStatus: $0.1, tunnelStatus: $0.2
            )
        }
        .skipRepeats()
        .startWithValues { [unowned objcBridge] newValue in

            objcBridge!.onSubscriptionBarViewStatusUpdate(
                ObjcSubscriptionBarViewState(swiftState: newValue)
            )
        }
        
        // Forwards VPN status changes to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] in
                objcBridge!.onVPNStatusDidChange($0)
            }
        
        // Monitors state of VPN status and tunnel intent.
        // If there's a mismatch when tunnel intent changes to start,
        // it alerts the user if the error is not resolves within a few seconds.
        self.lifetime += self.store.$value.signalProducer
            .map { appState -> Pair<VPNStatusWithIntent, ProviderManagerLoadState<PsiphonTPM>> in
                Pair(appState.vpnState.value.vpnStatusWithIntent, appState.vpnState.value.loadState)
            }
            .skipRepeats()
            .flatMap(.latest) { [unowned self] vpnStateTunnelLoadStatePair ->
                SignalProducer<Result<Utilities.Unit, ErrorEvent<ErrorRepr>>, Never> in
                
                guard case .loaded(_) = vpnStateTunnelLoadStatePair.second.value else {
                    return Effect(value: .success(.unit))
                }

                let compareValue = (current: vpnStateTunnelLoadStatePair.first.status.tunneled,
                                    expected: vpnStateTunnelLoadStatePair.first.intent)
                
                switch compareValue {
                case (current: .notConnected, expected: .start(transition: .none)):
                    let error = ErrorEvent(
                        ErrorRepr(repr: "Unexpected value '\(vpnStateTunnelLoadStatePair.second)'"),
                        date: self.dateCompare.getCurrentTime()
                    )
                    
                    // Waits for the specified amount of time before emitting the vpn status
                    // and tunnel intent mismatch error.
                    return Effect(value: .failure(error)).delay(
                        VPNHardCodedValues.vpnStatusAndTunnelIntentMismatchAlertDelay,
                        on: QueueScheduler.main
                    )
                    
                default:
                    return Effect(value: .success(.unit))
                }
            }
            .skipRepeats()
            .startWithValues { [unowned self] (result: Result<Utilities.Unit, ErrorEvent<ErrorRepr>>) in
                switch result {
                case .success(.unit):
                    break
                    
                case .failure(let errorEvent):
                    self.feedbackLogger.immediate(.error, "\(errorEvent)")
                    
                    self.objcBridge!.onVPNStateSyncError(
                        UserStrings.Tunnel_provider_sync_failed_reinstall_config()
                    )
                }
            }
        
        // Forwards SpeedBoost purchase expiry date (if the user is not subscribed)
        // to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map { [unowned self] appState -> SpeedBoostButton.SpeedBoostButtonViewModel in
                if case .subscribed(_) = appState.subscription.status {
                    return .inactive
                } else {
                    let activeSpeedBoost = appState.psiCashState.activeSpeedBoost(self.dateCompare)
                    if let expiry = activeSpeedBoost?.transaction.localTimeExpiry {
                        return .active(expiry)
                    } else {
                        return .inactive
                    }
                }
            }
            .skipRepeats()
            .combineLatest(
                with: self.store.$value.signalProducer.map(\.psiCashBalanceViewModel).skipRepeats()
            )
            .combineLatest(
                with: self.store.$value.signalProducer.map(\.psiCashState.libData?.accountType).skipRepeats()
            )
            .startWithValues { [unowned objcBridge] (tuple: ((SpeedBoostButton.SpeedBoostButtonViewModel, PsiCashBalanceViewModel), PsiCashAccountType?)) in
                
                let newValue = PsiCashWidgetView.ViewModel(
                    balanceViewModel: tuple.0.1,
                    speedBoostButtonModel: tuple.0.0,
                    accountType: tuple.1
                )
                
                objcBridge!.onPsiCashWidgetViewModelUpdate(
                    BridgedPsiCashWidgetBindingType(swiftValue: newValue))
                
            }
        
        self.lifetime += self.store.$value.signalProducer
            .map(\.vpnState.value.startStopState)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] startStopState in
                let value = VPNStartStopStatus.from(startStopState: startStopState)
                objcBridge!.onVPNStartStopStateDidChange(value)
            }
        
        // Forwards AppState `internetReachability` value to ObjCBridgeDelegate.
        self.lifetime += self.store.$value.signalProducer
            .map(\.internetReachability)
            .skipRepeats()
            .startWithValues { [unowned objcBridge] reachabilityStatus in
                objcBridge!.onReachabilityStatusDidChange(reachabilityStatus.networkStatus)
            }
        
        // Produces a SettingsViewModel type and passes
        // the value to the ObjCBridgeDelegte.
        self.lifetime += SignalProducer.combineLatest(
            self.store.$value.signalProducer.map(\.appReceipt.remoteReceiptRefreshState)
                .skipRepeats(),
            self.store.$value.signalProducer.map(\.subscription.status).skipRepeats(),
            self.store.$value.signalProducer.map(\.psiCashState.libData?.accountType).skipRepeats(),
            self.store.$value.signalProducer.map(\.psiCashState.isLoggingInOrOut),
            self.store.$value.signalProducer.map(\.vpnState.value.vpnStatus).skipRepeats()
        ).map {
            
            SettingsViewModel(
                receiptRefreshState: $0.0,
                subscriptionState: $0.1,
                psiCashAccountType: $0.2,
                isLoggingOut: $0.3 == .logout,
                vpnStatus: $0.4
            )
            
        }
        .startWithValues { [unowned objcBridge] model in
            objcBridge!.onSettingsViewModelDidChange(ObjcSettingsViewModel(model))
        }

        // Opens landing page whenever Psiphon tunnel is connected, with
        // change in value of `VPNState` tunnel intent.
        // Landing page should not be opened after a reconnection due to an In-App purchase.
        // This condition is implicitly handled, since reconnections do not cause a change
        // the in tunnel intent value.
        self.lifetime += self.store.$value.signalProducer
            .map(\.vpnState.value.tunnelIntent)
            .skipRepeats()
            .combinePrevious(initial: .none)
            .filter { (combined: Combined<TunnelStartStopIntent?>) -> Bool in
                
                switch (previous: combined.previous, current: combined.current) {
                case (previous: .none, current: .start(transition: .none)):
                    // First connection of the first launch of the app should
                    // not present the landing page.
                    // NOTE: This method has a minor false-positive where `tunnelIntent` is nil
                    // after launch if a VPN config is not installed.
                    return false
                case (previous: .stop, current: .start(transition: .none)):
                    return true
                case (previous: .start(transition: .restart), current: .start(transition: .none)):
                    return true
                default:
                    return false
                }
            }
            .flatMap(.latest) { [unowned store] _ in
                // Observes tunnel connected events after the user has switched
                // tunnel intent to `.start(transition: _)`.
                store!.$value.signalProducer
                    .map(\.vpnState.value.providerVPNStatus)
                    .skipRepeats()
                    .filter { $0 == .connected }
                    .take(first: 1)
                    .map(value: AppAction.landingPage(.tunnelConnectedAfterIntentSwitchedToStart))
            }
            .send(store: self.store)

        // Displays alerts related to PsiCash accounts login and logout events.
        self.lifetime += self.store.$value.signalProducer
            .map(\.psiCashState.pendingAccountLoginLogout)
            .skipRepeats()
            .startWithValues { [unowned store] maybeLoginLogoutEvent in
                guard let loginLogoutEvent = maybeLoginLogoutEvent else {
                    return
                }

                let maybeAlert: AlertType?
                
                switch loginLogoutEvent.wrapped {
                case .pending(_):
                    maybeAlert = .none
                    
                case let .completed(.left(completedLoginEvent)):
                    // PsiCash Account Login
                    
                    switch completedLoginEvent {
                    case let .success(loginResponse):
                        if loginResponse.lastTrackerMerge {
                            maybeAlert = .psiCashAccountAlert(.loginSuccessLastTrackerMergeAlert)
                        } else {
                            maybeAlert = .none
                        }

                    case let .failure(errorEvent):
                        switch errorEvent.error {
                        case .tunnelNotConnected:
                            maybeAlert = .psiCashAccountAlert(.tunnelNotConnectedAlert)

                        case .requestError(.errorStatus(let psiCashServerErrorStatus)):
                            
                            switch psiCashServerErrorStatus {
                            case .invalidCredentials:
                                maybeAlert = .psiCashAccountAlert(.incorrectUsernameOrPasswordAlert)
                                
                            case .badRequest:
                                maybeAlert = .psiCashAccountAlert(.accountLoginBadRequestAlert)
                                
                            case .serverError:
                                maybeAlert = .psiCashAccountAlert(.accountLoginServerErrorAlert)
                            }
                            
                        case .requestError(.requestCatastrophicFailure(_)):
                            maybeAlert = .psiCashAccountAlert(.accountLoginCatastrophicFailureAlert)
                        }
                    }

                case let .completed(.right(completedLogoutEvent)):
                    // PsiCash Account Logout
                    
                    switch completedLogoutEvent {
                    case .success(_):
                        maybeAlert = .psiCashAccountAlert(.logoutSuccessAlert)

                    case .failure(_):
                        maybeAlert = .psiCashAccountAlert(.accountLogoutCatastrophicFailureAlert)
                    }
                    
                }

                // Sends alert to store if one has been set.
                if let alert = maybeAlert {
                    let alertEvent = loginLogoutEvent.map { _ -> AlertType in
                        alert
                    }
                    store!.send(.mainViewAction(.presentAlert(alertEvent)))
                }
            }
        
        
        // TODO: Replace with tuple once equatable synthesis for tuples is added to Swift.
        struct _TokensExpiredData: Equatable {
            // PsiCash account completed login/logout event.
            let accountLoginLogoutCompletedEvent: Event<PsiCashState.AccountLoginLogoutCompleted>?
            let accountType: PsiCashAccountType
        }
        
        // Scans PsiCash libdata for when the login expires (i.e. token expiring),
        // alerting the user if state transitioned from having tokens
        // into logged out state.
        self.lifetime += self.store.$value.signalProducer
            .map(\.psiCashState)
            .skipRepeats()  // Reduces number of redundant items downstream.
            .compactMap { psiCashState -> _TokensExpiredData? in
                
                // Removes PsiCash library non-initialized value (literal `nil`) from signal.
                guard let accountType = psiCashState.libData?.accountType else {
                    return nil
                }
                
                // Removes PsiCash account pending login/logout events from signal,
                // to simplify the state space by removing states we don't care about.
                switch psiCashState.pendingAccountLoginLogout {
                case .none:
                    return _TokensExpiredData(accountLoginLogoutCompletedEvent: nil,
                                              accountType: accountType)
                case .some(let loginLogoutEvent):
                    switch loginLogoutEvent.wrapped {
                    case .pending(_):
                        return nil
                    case let .completed(loginLogoutCompleted):
                        let loginLogoutCompletedEvent = Event(loginLogoutCompleted,
                                                              date: loginLogoutEvent.date)
                        return _TokensExpiredData(
                            accountLoginLogoutCompletedEvent: loginLogoutCompletedEvent,
                            accountType: accountType
                        )
                    }
                }
                
            }
            .skipRepeats()  // Scan operator below assumes that events are unique
                            // in determining the expiry date of account token.
            .scan(nil) { (prvCombined, cur) -> (_TokensExpiredData, Date?)? in
                
                // Scans upstream signal for the last two values emitted.
                // Since RxSwift doens't have a buffer operator, the returned tuple's
                // first element is always `cur`, and second element is to be used downstream,
                // and ignroed by this scan operator.
                //
                // This operator returns date of when the PsiCah account token expired.
                
                // Ignores initial nil value of `prv`, since we're interested in state change.
                guard let prv = prvCombined?.0 else {
                    return (cur, nil)
                }
                
                // Ensure that events are unique.
                guard prv != cur else {
                    fatalError("programming error")
                }
                
                // If we are newly transitioning into a logged out state due
                // to account token expiry, let the user know
                guard
                    case .account(loggedIn: false) = cur.accountType,
                    case .account(loggedIn: true) = prv.accountType,
                    cur.accountLoginLogoutCompletedEvent == prv.accountLoginLogoutCompletedEvent
                else {
                    // Either the user has logged out,
                    // or logged in (which would be a programming error).
                    return (cur, nil)
                }
                
                // User is logged out due to token expiry, because there has been
                // no manual logout event (since `prv`), and the user cannot login if
                // the previous state (`prv`) is logged in.
                
                // Unique timestamp of token expiry.
                let tokenExpiryDate = Date()
                return (cur, tokenExpiryDate)
                
            }
            .map {
                $0?.1 // `Date?` field - account token expiry date
            }
            .startWithValues { [unowned store] maybeAccountTokenExpired in
                guard let date = maybeAccountTokenExpired else {
                    return
                }
                let alertEvent = AlertEvent(.psiCashAccountAlert(.accountTokensExpiredAlert),
                                            date: date)
                store!.send(.mainViewAction(.presentAlert(alertEvent)))
            }

        
        if Debugging.printAppState {

            self.lifetime += self.store.$value.signalProducer
                .map(\AppState.vpnState.value.tunnelIntent)
                .skipRepeats()
                .startWithValues { value in
                    var output = ""
                    dump(value, to: &output)
                    print("* -> \(removedCommonPackageNames(output))")
                }
            
        }
        
    }
    
    @objc func applicationDidBecomeActive(_ application: UIApplication) {
        
        guard case .iOS = platform.current else {
            return
        }
        
        applicationDidBecomeActive()
    }
    
    @objc func applicationWillResignActive(_ application: UIApplication) {
        
        guard case .iOS = platform.current else {
            return
        }
        
        applicationWillResignActive()
    }
    
    @objc func applicationWillEnterForeground(_ application: UIApplication) {
        
        guard case .iOS = platform.current else {
            return
        }
        
        applicationWillEnterForeground()
    }
    
    @objc func applicationDidEnterBackground(_ application: UIApplication) {
        
        guard case .iOS = platform.current else {
            return
        }
        
        applicationDidEnterBackground()
    }
    
    @objc func applicationWillTerminate(_ application: UIApplication) {
        
        if let observer = self.appLangChagneObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        self.environmentCleanup?()
        
    }

    @objc func application(_ app: UIApplication,
                           open url: URL,
                           options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        
        return deepLinkingNavigator.handle(url: url)
    }
    
    /// Retruns top-most view controller that can present another view controller (i.e. is not being dismissed)
    @objc func getTopActiveViewController() -> UIViewController {
        
        var vc = UIApplication.shared.keyWindow!.rootViewController!
        
        while let presentedVC = vc.presentedViewController, !presentedVC.isBeingDismissed {
            vc = presentedVC
        }
        
        return vc
        
    }

    @objc func presentPsiCashAccountViewController(withPsiCashScreen: Bool) {
        
        if withPsiCashScreen {
            self.store.send(.mainViewAction(
                                .presentPsiCashScreen(initialTab: .speedBoost, animated: true)))
        }
        
        self.store.send(.mainViewAction(.presentPsiCashAccountScreen))
        
    }
    
    @objc func presentPsiCashViewController(_ initialTab: PsiCashScreenTab) {
        self.store.send(.mainViewAction(.presentPsiCashScreen(initialTab: initialTab)))
    }
    
    @objc func presentPsiCashAccountManagement() {
        self.store.send(.mainViewAction(.presentPsiCashAccountManagement))
    }
    
    @objc func loadingScreenDismissSignal(_ completionHandler: @escaping () -> Void) {
                
        self.store.$value.signalProducer
            .filter { appState in
                
                // Filters out AppState's where values are not known yet.
                //
                // The app is expected to display the loading screen,
                // while values of subscription status, VPN status, ...
                // are being initialized.
                
                return appState.unknownValuesInitialized
                
            }
            .map { (appState: AppState) -> Bool in
                
                // Returns true if loading screen can be dismissed given
                // the current AppState, otherwise false.
                
                if case .iOSAppOnMac = self.platform.current {
                    // No loading screen is necessary currently on Mac.
                    return true
                }
                
                if appState.appDelegateState.onboardingCompleted == false {
                    // If onboarding is not competed, dismiss loading screen.
                    // Note: Loading screen should not be displayed,
                    // if user onboarding has not been completed.
                    return true
                }
                
                if appState.vpnState.value.loadState.connectionStatus.tunneled != .notConnected {
                    // If tunnel status is not "notConnected", dismiss loading screen.
                    return true
                }
                
                if case .subscribed(_) = appState.subscription.status {
                    // If user is subscribed, dismiss loading screen.
                    return true
                }
                
                if case .some(_) = appState.psiCashState.activeSpeedBoost(self.dateCompare) {
                    // If user has an active Speed Boost, dismiss loading screen.
                    return true
                }
                
                return true
                                
            }
            .skipRepeats()
            .flatMap(.race) { dismiss -> SignalProducer<Bool, Never> in
                
                // Forward only events from the first inner stream that sends an event.
                // Any other in-flight inner streams is disposed of when the winning
                // inner stream is determined.
                //
                // In this case, if called with dismiss being true, and previously the timer signal
                // was emitted, the timer signal will be disposed.
                
                if dismiss {
                    return SignalProducer(value: true)
                } else {
                    return SignalProducer.timer(interval: .seconds(10), on: QueueScheduler.main)
                        .map(value: true)
                }
                
            }
            .take(first: 1) // Upstream value is assumed to always be true.
            .startWithValues { _ in
                // Upstream value is assumed to always be true.
                completionHandler()
            }
        
    }
    
    @objc func makeSubscriptionBarView() -> SubscriptionBarView {
        SubscriptionBarView { [unowned objcBridge, store] state in
            switch state.authState {
            case .notSubscribed, .subscribedWithAuth:
                objcBridge?.presentSubscriptionIAPViewController()

            case .failedRetry:
                store?.send(.appReceipt(.readLocalReceiptFile))

            case .pending:
                if state.tunnelStatus == .notConnected {
                    objcBridge?.startStopVPN()
                }
            }
        }
    }
    @objc func makeOnboardingViewControllerWithStagesNotCompleted(
        _ completionHandler: @escaping (OnboardingViewController) -> Void
    ) -> OnboardingViewController? {
        
        // Finds stages that are not completed by the user.
        let stagesNotCompleted = OnboardingStage.findStagesNotCompleted(
            completedStages: self.userDefaultsConfig.onboardingStagesCompletedTyped
        )
        
        guard !stagesNotCompleted.isEmpty else {
            return nil
        }
        
        return OnboardingViewController(
            platform: platform,
            userDefaultsConfig: self.userDefaultsConfig,
            mainBundle: .main,
            onboardingStages: stagesNotCompleted,
            feedbackLogger: self.feedbackLogger,
            installVPNConfig: self.installVPNConfig,
            onOnboardingFinished: { [unowned self] onboardingViewController in
                
                self.store.send(.appDelegateAction(.onboardingCompleted))
                
                completionHandler(onboardingViewController)
                
            }
        )
    }
    
    @objc func completedAllOnboardingStages() -> Bool {
        // Finds stages that are not completed by the user.
        let stagesNotCompleted = OnboardingStage.findStagesNotCompleted(
            completedStages: self.userDefaultsConfig.onboardingStagesCompletedTyped)
        
        return stagesNotCompleted.isEmpty
    }
    
    @objc func isNewInstallation() -> Bool {
        guard let newInstallation = self.appUpgrade.newInstallation else {
            fatalError()
        }
        return newInstallation
    }
    
    @objc func getCustomRewardData(_ callback: @escaping (CustomData?) -> Void) {
        callback(self.psiCashLib.getRewardActivityData().successToOptional())
    }
    
    @objc func refreshAppStoreReceipt() -> Promise<Error?>.ObjCPromise<NSError> {
        let promise = Promise<Result<Utilities.Unit, SystemErrorEvent<Int>>>.pending()
        let objcPromise = promise.then { result -> Error? in
            return result.failureToOptional()?.error
        }
        self.store.send(.appReceipt(.remoteReceiptRefresh(optionalPromise: promise)))
        return objcPromise.asObjCPromise()
    }
    
    @objc func buyAppStoreSubscriptionProduct(
        _ skProduct: SKProduct
    ) -> Promise<ObjCIAPResult>.ObjCPromise<ObjCIAPResult> {
        let promise = Promise<ObjCIAPResult>.pending()
        
        do {
            let appStoreProduct = try AppStoreProduct.from(
                skProduct: skProduct,
                isSupportedProduct: self.supportedProducts.isSupportedProduct(_:)
            )
            
            guard case .subscription = appStoreProduct.type else {
                fatalError()
            }
            
            self.store.send(.iap(.purchase(product: appStoreProduct, resultPromise: promise)))
            
        } catch {
            self.feedbackLogger.fatalError(
                "Unknown subscription product identifier '\(skProduct.productIdentifier)'")
        }
        
        return promise.asObjCPromise()
    }
    
    @objc func getAppStoreSubscriptionProductIDs() -> Set<String> {
        return self.supportedProducts.supported[.subscription]!.rawValues
    }
    
    @objc func switchVPNStartStopIntent()
    -> Promise<SwitchedVPNStartStopIntent>.ObjCPromise<SwitchedVPNStartStopIntent>
    {
        let promise = Promise<SwitchedVPNStartStopIntent>.pending()
        
        let syncedVPNState: SignalProducer<VPNProviderManagerState<PsiphonTPM>, Never> =
            self.store.$value.signalProducer
            .map(\.vpnState.value)
            .filter { vpnProviderManagerState -> Bool in
                if case .completed(_) = vpnProviderManagerState.providerSyncResult {
                    return true
                } else {
                    return false
                }
            }
            .take(first: 1)
        
        syncedVPNState.map {
            SwitchedVPNStartStopIntent.make(fromProviderManagerState: $0)
        }.startWithValues { newIntentValue in
            promise.fulfill(newIntentValue)
        }
        
        return promise.asObjCPromise()
    }
    
    @objc func sendNewVPNIntent(_ value: SwitchedVPNStartStopIntent) {
        switch value.switchedIntent {
        case .start(transition: .none):
            self.store.send(vpnAction: .tunnelStateIntent(
                intent: .start(transition: .none), reason: .userInitiated
            ))
        case .stop:
            self.store.send(vpnAction: .tunnelStateIntent(
                intent: .stop, reason: .userInitiated
            ))
        default:
            self.feedbackLogger.fatalError("Unexpected state '\(value.switchedIntent)'")
            return
        }
    }
        
    @objc func restartVPNIfActive() {
        self.store.send(vpnAction: .tunnelStateIntent(
            intent: .start(transition: .restart), reason: .userInitiated
        ))
    }
    
    @objc func reinstallVPNConfig() {
        self.store.send(vpnAction: .reinstallVPNConfig)
    }

    typealias IndexedPsiphonTPMLoadState = Indexed<ProviderManagerLoadState<PsiphonTPM>.LoadState>
    
    @objc func installVPNConfigWithPromise() ->
    Promise<VPNConfigInstallResultWrapper>.ObjCPromise<VPNConfigInstallResultWrapper>
    {
        // Maps Swift type `Promise<VPNConfigInstallResult>` to equivalent ObjC type.
        self.installVPNConfig().then { VPNConfigInstallResultWrapper($0) }.asObjCPromise()
    }
    
    @objc func logOutPsiCashAccount() {
        self.store.send(.psiCash(.accountLogout))
    }
    
    @objc func restorePurchases(_ completionHandler: @escaping (NSError?) -> Void) {
        let promise = Promise<Result<Utilities.Unit, SystemErrorEvent<Int>>>.pending()
        
        self.store.send(.appReceipt(.remoteReceiptRefresh(optionalPromise: promise)))
        
        promise.then { result in
            if let error = result.failureToOptional()?.error.errorInfo {
                let nsError = NSError(
                    domain: error.domain,
                    code: error.errorCode,
                    userInfo: [NSLocalizedDescriptionKey: error.errorDescription ?? ""])
                
                completionHandler(nsError)
                
            } else {
                completionHandler(nil)
            }
        }
        
    }
    
    @objc func getLocaleForCurrentAppLanguage() -> NSLocale {
        return self.userDefaultsConfig.localeForAppLanguage as NSLocale
    }

    @objc func userSubmittedFeedback(selectedThumbIndex: Int,
                                     comments: String,
                                     email: String,
                                     uploadDiagnostics: Bool) {
        self.store.send(
            .feedbackAction(
                .userSubmittedFeedback(selectedThumbIndex: selectedThumbIndex,
                                       comments: comments,
                                       email: email,
                                       uploadDiagnostics: uploadDiagnostics)))
    }

    @objc func versionLabelText() -> String {

        let shortVersionString: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "(nil)"

        // If this build is not a release build, additional
        // build metadata can be displayed alongside the version label.

        let postfix: String

        switch Debugging.buildConfig {

        case .debug:
            postfix = "-debug"

        case .devRelease:

            let bundleVersion: String = Bundle.main.object(  
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "(nil)"

            postfix = "-(\(bundleVersion))-dev-release"

        case .release:
            postfix = ""

        }

        return "V.\(shortVersionString)\(postfix)"
    }

    func connectButtonTappedFromSettings() {
        // This is a round-about way of calling into ObjC AppDelegate through Swift.
        // This is to make transition to Swift-only codebase easier in the future.
        self.objcBridge.dismiss(screen: .settings) { [unowned self] in
            self.objcBridge.startStopVPN()
        }
    }
    
    // Handles Darwin notifications sent to the host app from the Network Extension process.
    @objc func networkExtensionNotification(_ message: String) {
        
        // Maps the string message type to an enumerable value.
        let typedMessage = NotifierNetworkExtensionMessage(rawValue: message)
        
        switch typedMessage {
            
        case .tunnelConnected:
            self.store.send(vpnAction: .syncWithProvider(
                reason: .providerNotificationPsiphonTunnelConnected))
            
        case .availableEgressRegions:
            let regions = self.sharedDB.emittedEgressRegions()
            RegionAdapter.sharedInstance().onAvailableEgressRegions(regions)
            
        case .networkConnectivityFailed, .networkConnectivityResolved:
            break
            
        case .disallowedTrafficAlert:
            self.store.send(.appDelegateAction(.checkForDisallowedTrafficAlertNotification))
            
        case .isHostAppProcessRunning:
            Notifier.sharedInstance().post(NotifierHostAppProcessRunning)

        default:
            feedbackLogger.immediate(.error, "Unknown Notifier message: '\(message)'")
            
        }
        
    }
    
    // Core Data
    @objc func sharedCoreData() -> SharedCoreData {
        self.sharedAuthCoreData
    }
    
#if DEBUG || DEV_RELEASE
    @objc func getPsiCashStoreDir() -> String? {
        self.appSupportFileStore.psiCashFileStoreRootPath
    }
#endif
    
}
