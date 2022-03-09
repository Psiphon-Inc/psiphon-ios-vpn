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
import PsiCashClient
import Utilities
import ReactiveSwift
import UIKit
import PsiphonClientCommonLibrary
import SafariServices

enum MainViewAction: Equatable {

    case psiCashViewAction(PsiCashViewAction)
    
    case reloadAppUI(openSettingsScreen: Bool)
    
    case applicationDidBecomeActive
    
    case openExternalURL(URL)
    
    // MARK: Alerts
    case presentAlert(AlertEvent)
    case _presentAlertResult(newState: PresentationState<AlertEvent>)
    case _alertButtonTapped(AlertEvent, AlertAction)
    
    /// Represents screens presented in the app (either modally, or as a child view controller).
    ///  - Note: Currently this is a subset of all the view controllers.
    enum Screen: Equatable {
        case psiCashStore
        case psiCashAccountLogin
        case psiCashAccountMgmt
        
        /// - Parameter forceReconnect: non-nil value when the settings screen is dismissed, otherwise `nil`.
        case settings(forceReconnect: Bool?)
        
        case feedback
    }

    case screenDidLoad(Screen)
    case screenDismissed(Screen)
    
    case presentPsiCashStore(initialTab: PsiCashScreenTab, animated: Bool = true)
    
    case presentPsiCashAccountExplainer
    
    case presentPsiCashAccountManagement
    
    case presentSubscriptionScreen
    
    case presentSettingsScreen
    
    /// Presents feedback screen modally.
    /// - Parameter errorInitiated: `True` if the feedback dialog is initiated due to an error condition.
    case presentModalFeedbackScreen(errorInitiated: Bool)
    
}

/// Represents the view state of the modal feedback dialog.
struct ModalFeedbackViewState: Equatable {
    
    /// True if the feedback modal is initiated by an error condition within the app.
    var isErrorInitiated: Bool
    
}

/// - Note: All view controller's whos presented state is tracked in `MainViewState`,
/// should ideally subclass `ReactiveViewController` to get the correct behaviour when being dismissed.
struct MainViewState: Equatable {
    
    /// Set of alert messages presented, or to be presented (including failed ones).
    /// - Note: Two elements of`alertMessages` are equal if their `AlertEvent` values are equal.
    var alertMessages = Set<PresentationState<AlertEvent>>()
    
    var psiCashStoreViewState: PsiCashStoreViewState? = nil
    
    /// Represents presentation state of PsiCash accounts screen.
    var psiCashAccountLoginIsPresented: Pending<Bool> = .completed(false)
    
    /// Represents presentation state of the settings screen.
    var settingsIsPresented: Pending<Bool> = .completed(false)
    
    /// Represents presentation state of the feedback screen.
    /// This is state of a modally presented feedback screen, and is separate
    /// from `FeedbackViewController` presented by the `PsiphonSettingsViewController`.
    ///
    /// - Note: `.completed(.none)` represents a state where feedback dialog is not displayed.
    ///
    var feedbackModalIsPresented: PendingValue<ModalFeedbackViewState, ModalFeedbackViewState?> = .completed(.none)
    
}

struct MainViewReducerState: Equatable {
    var mainView: MainViewState
    let subscriptionState: SubscriptionState
    let psiCashAccountType: PsiCashAccountType?
    let appLifecycle: AppLifecycle
    let tunnelConnectedStatus: TunnelConnectedStatus
}

extension MainViewReducerState {
    var psiCashViewReducerState: PsiCashStoreViewReducerState? {
        get {
            guard let psiCashState = self.mainView.psiCashStoreViewState else {
                return nil 
            }
            return PsiCashStoreViewReducerState(
                viewState: psiCashState,
                psiCashAccountType: self.psiCashAccountType,
                tunnelConnectedStatus: self.tunnelConnectedStatus
            )
        }
        set {
            self.mainView.psiCashStoreViewState = newValue?.viewState
        }
    }
}

struct MainViewEnvironment {
    
    let userConfigs: UserDefaultsConfig
    let psiCashStore: (PsiCashAction) -> Effect<Never>
    let psiCashStoreViewEnvironment: PsiCashStoreViewEnvironment
    let getTopActiveViewController: () -> UIViewController
    let feedbackLogger: FeedbackLogger
    let rxDateScheduler: DateScheduler
    let makeSubscriptionViewController: () -> SubscriptionViewController
    let dateCompare: DateCompare
    let addToDate: (Calendar.Component, Int, Date) -> Date?
    let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    let psiCashEffects: PsiCashEffects
    
    let tunnelIntentStore: (TunnelStartStopIntent) -> Effect<Never>
    
    let serverRegionStore: (ServerRegionAction) -> Effect<Never>
    
    let reloadMainScreen: () -> Effect<Utilities.Unit>
    
    let makePsiCashStoreViewController: () -> PsiCashStoreViewController
    let makePsiCashAccountExplainerViewController: () -> PsiCashAccountExplainerViewController
    let makeSettingsViewController: () -> NavigationController
    let makeFeedbackViewController: ([String: Any]) -> NavigationController
    
}

let mainViewReducer = Reducer<MainViewReducerState, MainViewAction, MainViewEnvironment> {
    state, action, environment in
    
    switch action {
        
    case .psiCashViewAction(let psiCashAction):
        switch state.psiCashViewReducerState {
        case .none:
            return []
        case .some(_):
            let effects = psiCashStoreViewReducer(
                &state.psiCashViewReducerState!, psiCashAction, environment.psiCashStoreViewEnvironment
            )
            
            return effects.map { $0.map { MainViewAction.psiCashViewAction($0) } }
        }
        
    case .reloadAppUI(openSettingsScreen: let openSettingsScreen):
        
        return [
            // Updates RegionAdapter's localized region titles.
            // It is assumed that app language has changed at this point.
           .fireAndForget {
                RegionAdapter.sharedInstance().reloadTitlesForNewLocalization()
            },
           
           environment.reloadMainScreen().flatMap(.latest, { _ in
               if openSettingsScreen {
                   return Effect(value: .presentSettingsScreen)
               } else {
                   return .empty
               }
           })
           
        ]
        
    case .applicationDidBecomeActive:
        let failedMessages = state.mainView.alertMessages.filter {
            if case .failedToPresent(_) = $0.state {
                return true
            } else {
                return false
            }
        }
        
        guard failedMessages.count > 0 else {
            return []
        }
        
        let failedMessagesAlertTypes = failedMessages.map(\.viewModel.wrapped)

        return [
            environment.feedbackLogger.log(
                .warn, "presenting previously failed alert messages: '\(failedMessagesAlertTypes)'")
                .mapNever()
        ]
        +
        failedMessages.map {
            Effect(value: .presentAlert($0.viewModel))
        }

    case .openExternalURL(let url):
        return [
            .fireAndForget {
                
                let webview = WebViewController(
                    baseURL: url,
                    showOpenInBrowser: true,
                    feedbackLogger: environment.feedbackLogger,
                    tunnelStatusSignal: environment.tunnelStatusSignal,
                    tunnelProviderRefSignal: environment.tunnelConnectionRefSignal,
                    onDidLoad: nil,
                    onDismissed: nil
                )
                
                let topVC = environment.getTopActiveViewController()
                let nav = PsiNavigationController(rootViewController: webview,
                                                  applyPsiphonStyling: false)
                topVC.present(nav, animated: true, completion: nil)
                
            }
        ]

    case let .presentAlert(alertEvent):
        
        if case .reportSeriousErrorAlert = alertEvent.wrapped {
            
            // Ignores present alert action if the feedback screen is already displayed.
            guard case .completed(.none) = state.mainView.feedbackModalIsPresented else {
                return []
            }
            
            // Adds 24 hours to the last time the alert was presented (if any),
            // If less 24 hours has passed, the request to present an alert is ignored.
            // This is important so that if the app misbehaves, the users are not bombarded
            // with this type of alert.
            if let lastErrorAlertDate = environment.userConfigs.lastErrorConditionFeedbackRequestDate {
                if let nextAllowedDate = environment.addToDate(.hour, 24, lastErrorAlertDate) {
                    if environment.dateCompare.compareDates(alertEvent.date, nextAllowedDate, .second) == .orderedAscending {
                        return []
                    }
                }
            }
            
        }

        // Heuristic for bounds-check with and garbage collection on alertMessages set.
        // Removes old alert messages that have already been presented.
        // 100 is some arbitrary large number.
        if state.mainView.alertMessages.count > 100 {
            let currentDate = environment.dateCompare.getCurrentTime()
            guard let anHourAgo = environment.addToDate(.hour, -1, currentDate) else {
                environment.feedbackLogger.fatalError("unexpected value")
                return []
            }

            let oldAlerts = state.mainView.alertMessages.filter {
                // Retruns true for any alert event that has already been presented,
                // and is older than anHourAgo.
                $0.state == .didPresent &&
                    environment.dateCompare.compareDates($0.viewModel.date, anHourAgo, .minute) ==
                    .orderedAscending
            }

            state.mainView.alertMessages.subtract(oldAlerts)
        }

        let maybeMatchingEvent = state.mainView.alertMessages.first {
            $0.viewModel == alertEvent
        }

        switch maybeMatchingEvent?.state {
        case .notPresented, .willPresent, .didPresent:
            // Alert was presented, or will be presented.
            return []

        case .none, .failedToPresent(.applicationNotActive):

            // This guard ensures that alert dialog is presented successfully,
            // given app's current lifecycle.
            // If the app is in the background, view controllers can be presented, but
            // not seen by the user.
            // Also if an alert is presented while the app just launched, but before
            // the applicationDidBecomeActive(_:) callback, UIKit will fail
            // to present the view controller.
            guard case .didBecomeActive = state.appLifecycle else {
                state.mainView.alertMessages.update(
                    with: PresentationState(alertEvent, state: .failedToPresent(.applicationNotActive))
                )
                return []
            }
            
            // It is expected that the alert will be presented successfully.
            // So `lastErrorConditionFeedbackRequestDate` is updated after `appLifeCycle`
            // check.
            if case .reportSeriousErrorAlert = alertEvent.wrapped {
                environment.userConfigs.lastErrorConditionFeedbackRequestDate = alertEvent.date
            }

            // Alert is either new, or failed to present previously.
            state.mainView.alertMessages.update(
                with: PresentationState(alertEvent, state: .notPresented)
            )

            return [
                environment.feedbackLogger.log(.info, "Will present alert: \(alertEvent)")
                    .mapNever(),

                // Creates a UIAlertController based on the given alertEvent, and presents it
                // on top of the top most presented view controller.
                Effect { observer, _ in

                    let alertController = UIAlertController
                        .makeUIAlertController(
                            alertEvent: alertEvent,
                            onActionButtonTapped: { alertEvent, alertAction in
                                observer.send(value: ._alertButtonTapped(alertEvent, alertAction))
                                // Completes the signal as the UIAlertController has been dismissed.
                                observer.sendCompleted()
                            }
                        )

                    environment.getTopActiveViewController().present(
                        alertController,
                        animated: true,
                        completion: {
                            observer.send(value: ._presentAlertResult(
                                            newState: PresentationState(alertEvent,
                                                                        state: .didPresent)))

                            // `onActionButtonTapped` closure of makeUIAlertController
                            // is expected to be called after (this) `completion` closure is called.
                        }
                    )

                    observer.send(value: ._presentAlertResult(
                        newState: PresentationState(alertEvent, state: .willPresent)))
                }
            ]
        }

    case let ._presentAlertResult(newState: newState):

        guard
            let oldMember = state.mainView.alertMessages.update(with: newState)
        else {
            environment.feedbackLogger.fatalError("unexpected state")
            return []
        }
        
        var effects = [Effect<MainViewAction>]()

        // Verifies if oldMember has the expected value given newState.
        let expectedOldMemberState: PresentationState<AlertEvent>.State?
        switch newState.state {
        case .notPresented:
            expectedOldMemberState = nil

        case .failedToPresent(.applicationNotActive):
            expectedOldMemberState = .notPresented
            
            effects += environment.feedbackLogger.log(
                .error, "Failed to present alert since application not active: \(newState.viewModel)")
                .mapNever()
            
        case .willPresent:
            expectedOldMemberState = .notPresented

        case .didPresent:
            expectedOldMemberState = .willPresent
        }

        guard oldMember.state == expectedOldMemberState else {
            environment.feedbackLogger.fatalError("unexpected state")
            return effects
        }

        return effects

    case let ._alertButtonTapped(alertEvent, alertAction):

        // State check.
        let expectedCurrentState = PresentationState(alertEvent, state: .didPresent)
        guard state.mainView.alertMessages.contains(expectedCurrentState) else {
            environment.feedbackLogger.fatalError("unexpected state")
            return []
        }

        switch alertAction {
        case .dismissTapped:

            let alertType: AlertType = alertEvent.wrapped
            switch alertType {
            case .psiCashAccountAlert(.loginSuccessLastTrackerMergeAlert):
                // Dismisses PsiCashAccountViewController if it is top of the stack.
                return [
                    .fireAndForget {
                        let topVC = environment.getTopActiveViewController()
                        let searchResult = topVC.traversePresentingStackFor(
                            type: PsiCashAccountLoginViewController.self,
                            searchChildren: true
                        )

                        switch searchResult {
                        case .notPresent:
                            // No-op.
                            return
                        case .presentInStack(let viewController),
                             .presentTopOfStack(let viewController):
                            viewController.dismiss(animated: true, completion: nil)
                        }
                    }
                ]

            default:
                return []
            }

        case .addPsiCashTapped:
            // Note that "Add PsiCash" tab is only displayed only if PsiCashStoreViewController
            // is already presented (i.e. state.mainView.psiCashStoreViewState is not nil).
            return [ Effect(value: .psiCashViewAction(.switchTabs(.addPsiCash))) ]

        case let .disallowedTrafficAlertAction(a):
            switch a {
            case .speedBoostTapped:
                return [ Effect(value: .presentPsiCashStore(initialTab: .speedBoost)) ]
                
            case .subscriptionTapped:
                return [ Effect(value: .presentSubscriptionScreen) ]
            }
            
        case .sendErrorInitiatedFeedback:
            return [ Effect(value: .presentModalFeedbackScreen(errorInitiated: true)) ]
            
        }
        
    case .screenDidLoad(let screen):
        
        switch screen {
            
        case .psiCashAccountMgmt:
            return []
            
        case .psiCashStore:
            // Forced PsiCash RefreshState. This ensures updated balance is shown
            // even if the user is for example subscribed.
            return [
                environment.psiCashStore(.refreshPsiCashState(forced: true))
                    .mapNever()
            ]
            
        case .psiCashAccountLogin:
            state.mainView.psiCashAccountLoginIsPresented = .completed(true)
            return []
            
        case .settings(forceReconnect: _):
            state.mainView.settingsIsPresented = .completed(true)
            return []
            
        case .feedback:
            // `isModalFeedbackScreenShown` is expected to be in a `.pending(_)` state.
            guard case let .pending(feedbackViewState) = state.mainView.feedbackModalIsPresented else {
                fatalError()
            }
            
            state.mainView.feedbackModalIsPresented = .completed(feedbackViewState)
            
            return []
            
        }
        
    case .screenDismissed(let screen):
        
        switch screen {
            
        case .psiCashAccountMgmt:
            // PsiCash RefreshState after dismissal of Account Management screen.
            // This is necessary since the user might have updated their username, or
            // other account information.
            return [
                environment.psiCashStore(.refreshPsiCashState(forced: true))
                    .mapNever()
            ]
            
        case .psiCashStore:
            state.mainView.psiCashStoreViewState = .none
            return []
        
        case .psiCashAccountLogin:
            state.mainView.psiCashAccountLoginIsPresented = .completed(false)
            
            // if psiCashViewReducerState has value,then forwards
            // the PsiCash account dismissed event to psiCashStoreViewReducer.
            switch state.psiCashViewReducerState {
            case .none:
                return []
            case .some(_):
                let effects = psiCashStoreViewReducer(&state.psiCashViewReducerState!,
                                                      .dismissedPsiCashAccountScreen,
                                                      environment.psiCashStoreViewEnvironment)
                
                return effects.map { $0.map { MainViewAction.psiCashViewAction($0) } }
            }
            
        case .settings(let forceReconnect):
            state.mainView.settingsIsPresented = .completed(false)
            
            var effects = [Effect<MainViewAction>]()
            
            // Copies all settings, in case any setting has changed.
            effects += .fireAndForget {
                CopySettingsToPsiphonDataSharedDB.sharedInstance.copyAllSettings()
            }
            
            // Updates selected region, in case it has changed.
            effects += environment.serverRegionStore(.updateAvailableRegions)
                .mapNever()
            
            if forceReconnect ?? false {
                // Restarts VPN if settings have changed.
                effects += environment.tunnelIntentStore(.start(transition: .restart)).mapNever()
            }
            
            return effects
            
        case .feedback:
            state.mainView.feedbackModalIsPresented = .completed(.none)
            return []
            
        }
        
        
    case .presentPsiCashAccountManagement:
        
        return [
            
            Effect { observer, _ in
                
                let topVC = environment.getTopActiveViewController()
                
                let found = topVC
                    .traversePresentingStackFor(type: WebViewController.self, searchChildren: true)

                switch found {
                case .presentTopOfStack(_), .presentInStack(_):
                    // NO-OP
                    observer.sendCompleted()
                    return
                    
                case .notPresent:
                    
                    let url = environment.psiCashEffects
                        .getUserSiteURL(.accountManagement, webview: true)
                    
                    let webViewViewController = WebViewController(
                        baseURL: url,
                        feedbackLogger: environment.feedbackLogger,
                        tunnelStatusSignal: environment.tunnelStatusSignal,
                        tunnelProviderRefSignal: environment.tunnelConnectionRefSignal,
                        onDidLoad: {
                            observer.send(value: .screenDidLoad(.psiCashAccountMgmt))
                        },
                        onDismissed: {
                            observer.send(value: .screenDismissed(.psiCashAccountMgmt))
                            observer.sendCompleted()
                        }
                    )
    
                    webViewViewController.title = UserStrings.Psicash_account()
    
                    let vc = PsiNavigationController(rootViewController: webViewViewController)
                    topVC.present(vc, animated: true, completion: nil)
                    
                }
                
            }
            
        ]
        
    case let .presentPsiCashStore(initialTab, animated):
        // If psiCashStoreViewState is not nil, it implies the PsiCashStoreViewController is presented.
        guard case .none = state.mainView.psiCashStoreViewState else {
            return []
        }

        state.mainView.psiCashStoreViewState = PsiCashStoreViewState(
            psiCashIAPPurchaseRequestState: .none,
            activeTab: initialTab
        )

        var effects = [Effect<MainViewAction>]()
        
        return [
            
            // Presents PsiCashStoreViewController
            .fireAndForget {
                let topVC = environment.getTopActiveViewController()
                let vc = environment.makePsiCashStoreViewController()
                topVC.present(vc, animated: animated, completion: nil)
            }
        ]
        
    case .presentPsiCashAccountExplainer:
        
        // Skips presenting PsiCash Account screen if tunnel is not connected.
        // Note that this is a quick check for informing the user,
        // and PsiCash Account screen performs it's own last second tunnel checks
        // before making any API requests.
        //
        // Note this this check is independent of the check performed when
        // handling other actions such as `.signupOrLoginTapped`.
        guard case .connected = state.tunnelConnectedStatus else {

            // Informs user that tunnel is not connected.
            let alertEvent = AlertEvent(
                .psiCashAccountAlert(.tunnelNotConnectedAlert),
                date: environment.dateCompare.getCurrentTime()
            )
            
            return [
                Effect(value: .presentAlert(alertEvent))
            ]
            
        }
        
        return [
            .fireAndForget {
                _ = environment.getTopActiveViewController()
                    .presentIfTypeNotPresent(
                        builder: environment.makePsiCashAccountExplainerViewController,
                        navigationBar: true
                    )
            }
        ]
        
    case .presentSubscriptionScreen:
        
        return [
            .fireAndForget {
                _ = environment.getTopActiveViewController()
                    .presentIfTypeNotPresent(
                        builder: environment.makeSubscriptionViewController,
                        navigationBar: true,
                        animated: true
                    )
            }
        ]
        
        
    case .presentSettingsScreen:
        
        guard case .completed(false) = state.mainView.settingsIsPresented else {
            return []
        }
        
        state.mainView.settingsIsPresented = .pending
        
        return [
            .fireAndForget {
                let topVC = environment.getTopActiveViewController()
                let settingsViewController = environment.makeSettingsViewController()
                topVC.present(settingsViewController, animated: true, completion: nil)
            }
        ]
        
    case .presentModalFeedbackScreen(errorInitiated: let errorInitiated):
        
        guard case .completed(.none) = state.mainView.feedbackModalIsPresented else {
            return []
        }
        
        state.mainView.feedbackModalIsPresented =
            .pending(ModalFeedbackViewState(isErrorInitiated: errorInitiated))
        
        let associatedData: [String: Any] = ["errorInitiated": NSNumber(value: errorInitiated)]
        
        return [
            .fireAndForget {
                let topVC = environment.getTopActiveViewController()
                let vc = environment.makeFeedbackViewController(associatedData)
                topVC.present(vc, animated: true, completion: nil)
            }
        ]
        
    }
    
}

// MARK: Settings Delegate

/// `PsiphonFeedbackDelegate` bridges callbacks from `FeedbackViewController`
/// to Store actions.
final class PsiphonFeedbackDelegate: StoreDelegate<AppAction>, FeedbackViewControllerDelegate {
    
    func userSubmittedFeedback(
        _ selectedThumbIndex: Int,
        comments: String!,
        email: String!,
        uploadDiagnostics: Bool,
        viewController: FeedbackViewController!
    ) {
        
        let errorInitiated = viewController.associatedData?["errorInitiated"] as? NSNumber
        
        let submitFeedbackData = SubmitFeedbackData(
            selectedThumbIndex: selectedThumbIndex,
            comments: comments ?? "",
            email: email ?? "",
            uploadDiagnostics: uploadDiagnostics,
            errorInitiated: errorInitiated?.boolValue ?? false
        )
        
        storeSend(.feedbackAction(.userSubmittedFeedback(submitFeedbackData)))
        
    }
    
    func userPressedURL(_ URL: URL!) {
        storeSend(.mainViewAction(.openExternalURL(URL)))
    }
    
    func feedbackViewControllerWillDismiss() {
        storeSend(.mainViewAction(.screenDismissed(.feedback)))
    }
    
}

/// `SettingsViewControllerDelegate` bridges callbacks from `PsiphonSettingsViewController`
/// to Store actions.
final class SettingsViewControllerDelegate: StoreDelegate<AppAction>, PsiphonSettingsViewControllerDelegate {
    
    private let enableSettingsLinks: Bool
    private let feedbackDelegate: PsiphonFeedbackDelegate
    
    init(
        store: Store<Utilities.Unit, AppAction>,
        feedbackDelegate: PsiphonFeedbackDelegate,
        shouldEnableSettingsLinks: Bool
    ) {
        self.enableSettingsLinks = shouldEnableSettingsLinks
        self.feedbackDelegate = feedbackDelegate
        super.init(store: store)
    }
    
    func notifyPsiphonConnectionState() {
        // Ignored
    }
    
    func reloadAndOpenSettings() {
        storeSend(.mainViewAction(.reloadAppUI(openSettingsScreen: true)))
    }
    
    func settingsWillDismiss(withForceReconnect forceReconnect: Bool) {
        storeSend(.mainViewAction(.screenDismissed(.settings(forceReconnect: forceReconnect))))
    }
    
    func shouldEnableSettingsLinks() -> Bool {
        enableSettingsLinks
    }
    
    func hiddenSpecifierKeys() -> [String]! {
        return []
    }
    
    // MARK: FeedbackViewControllerDelegate
    
    func userSubmittedFeedback(
        _ selectedThumbIndex: Int,
        comments: String!,
        email: String!,
        uploadDiagnostics: Bool,
        viewController: FeedbackViewController!
    ) {
        feedbackDelegate.userSubmittedFeedback(
            selectedThumbIndex, comments: comments, email: email, uploadDiagnostics: uploadDiagnostics, viewController: viewController)
    }
    
    func userPressedURL(_ URL: URL!) {
        feedbackDelegate.userPressedURL(URL)
    }
    
}
