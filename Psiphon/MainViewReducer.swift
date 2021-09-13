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
    
    // MARK: PsiCash account management
    // PsiCash Account Management is presented in a webview.
    case presentPsiCashAccountManagement
    // PsiCash Account Management screen is dismissed.
    case _dismissedPsiCashAccountManagement

    // MARK: PsiCash screen
    case presentPsiCashScreen(initialTab: PsiCashScreenTab, animated: Bool = true)
    case _presentPsiCashScreenResult(willPresent: Bool)
    case dismissedPsiCashScreen
    
    // MARK: PsiCash account screen
    case presentPsiCashAccountScreen
    case _presentPsiCashAccountScreenResult(willPresent: Bool)
    case dismissedPsiCashAccountScreen
    
    // MARK: Settings screen
    case presentSettingsScreen
    case _presentSettingsScreenResult(willPresent: Bool)
    case dismissedSettingsScreen(forceReconnect: Bool)
    
    // MARK: Feedback screen
    /// Presents feedback screen modally. This is separate from feedback screen
    /// presented by `InAppSettingsKit` thourght `PsiphonSettingsViewController`.
    case presentModalFeedbackScreen
    case _presentModalFeedbackScreenResult(willPresent: Bool)
    case dismissedModalFeedbackScreen
    
}

struct MainViewState: Equatable {
    
    /// Set of alert messages presented, or to be presented (including failed ones).
    /// - Note: Two elements of`alertMessages` are equal if their `AlertEvent` values are equal.
    var alertMessages = Set<PresentationState<AlertEvent>>()
    
    var psiCashViewState: PsiCashViewState? = nil
    
    /// Represents presentation state of PsiCash accounts screen.
    var isPsiCashAccountScreenShown: Pending<Bool> = .completed(false)
    
    /// Represents presentation state of the settings screen.
    var isSettingsScreenShown: Pending<Bool> = .completed(false)
    
    /// Represents presentation state of the feedback screen.
    /// This is state of a modally presented feedback screen, and is separate
    /// from `FeedbackViewController` presented by the `PsiphonSettingsViewController`.
    var isModalFeedbackScreenShown: Pending<Bool> = .completed(false)
    
}

struct MainViewReducerState: Equatable {
    var mainView: MainViewState
    let subscriptionState: SubscriptionState
    let psiCashAccountType: PsiCashAccountType?
    let appLifecycle: AppLifecycle
    let tunnelConnectedStatus: TunnelConnectedStatus
}

extension MainViewReducerState {
    var psiCashViewReducerState: PsiCashViewReducerState? {
        get {
            guard let psiCashState = self.mainView.psiCashViewState else {
                return nil 
            }
            return PsiCashViewReducerState(
                viewState: psiCashState,
                psiCashAccountType: self.psiCashAccountType,
                tunnelConnectedStatus: self.tunnelConnectedStatus
            )
        }
        set {
            self.mainView.psiCashViewState = newValue?.viewState
        }
    }
}

struct MainViewEnvironment {
    let psiCashStore: (PsiCashAction) -> Effect<Never>
    let psiCashViewEnvironment: PsiCashViewEnvironment
    let getTopActiveViewController: () -> UIViewController
    let feedbackLogger: FeedbackLogger
    let rxDateScheduler: DateScheduler
    let makePsiCashViewController: () -> PsiCashViewController
    let makeSubscriptionViewController: () -> UIViewController
    let dateCompare: DateCompare
    let addToDate: (Calendar.Component, Int, Date) -> Date?
    let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    let psiCashEffects: PsiCashEffects
    
    let tunnelIntentStore: (TunnelStartStopIntent) -> Effect<Never>
    
    let serverRegionStore: (ServerRegionAction) -> Effect<Never>
    
    let reloadMainScreen: () -> Effect<Utilities.Unit>
    
    /// Makes `PsiCashAccountViewController` as root of a `UINavigationController`.
    let makePsiCashAccountViewController: () -> UIViewController
    
    /// Makes `SettingsViewController` as root of a `UINavigationController`.
    let makeSettingsViewController: () -> UIViewController
    
    /// Makes `FeedbackViewController` as root of a `UINavigationController`.
    let makeFeedbackViewController: () -> UIViewController
    
}

let mainViewReducer = Reducer<MainViewReducerState, MainViewAction, MainViewEnvironment> {
    state, action, environment in
    
    switch action {
        
    case .psiCashViewAction(let psiCashAction):
        switch state.psiCashViewReducerState {
        case .none:
            return []
        case .some(_):
            let effects = psiCashViewReducer(
                &state.psiCashViewReducerState!, psiCashAction, environment.psiCashViewEnvironment
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
                let topVC = environment.getTopActiveViewController()
                let safariVC = SFSafariViewController(url: url)
                topVC.present(safariVC, animated: true, completion: nil)
            }
        ]

    case let .presentAlert(alertEvent):

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
                            type: PsiCashAccountViewController.self,
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
            // Note that "Add PsiCash" tab is only displayed only if PsiCashViewController
            // is already presented (i.e. state.mainView.psiCashViewState is not nil).
            return [ Effect(value: .psiCashViewAction(.switchTabs(.addPsiCash))) ]

        case let .disallowedTrafficAlertAction(a):
            switch a {
            case .speedBoostTapped:
                return [ Effect(value: .presentPsiCashScreen(initialTab: .speedBoost)) ]
            case .subscriptionTapped:

                return [
                    .fireAndForget {
                        let topVC = environment.getTopActiveViewController()

                        let found = topVC
                            .traversePresentingStackFor(type: IAPViewController.self, searchChildren: true)

                        switch found {
                        case .presentTopOfStack(_), .presentInStack(_):
                            // NO-OP
                            break
                        case .notPresent:
                            let vc = environment.makeSubscriptionViewController()
                            topVC.present(vc, animated: true, completion: nil)
                        }
                    }
                ]
            }
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
                        onDismissed: {
                            observer.send(value: ._dismissedPsiCashAccountManagement)
                            observer.sendCompleted()
                        }
                    )
    
                    webViewViewController.title = UserStrings.Psicash_account()
    
                    let vc = UINavigationController(rootViewController: webViewViewController)
                    topVC.present(vc, animated: true, completion: nil)
                    
                }
                
            }
            
        ]
        
    case ._dismissedPsiCashAccountManagement:
        
        // PsiCash RefreshState after dismissal of Account Management screen.
        // This is necessary since the user might have updated their username, or
        // other account information.
        return [
            environment.psiCashStore(.refreshPsiCashState(forced: true))
                .mapNever()
        ]

    case let .presentPsiCashScreen(initialTab, animated):
        // If psiCashViewState is not nil, it implies the PsiCashViewController is presented.
        guard case .none = state.mainView.psiCashViewState else {
            return []
        }

        state.mainView.psiCashViewState = PsiCashViewState(
            psiCashIAPPurchaseRequestState: .none,
            activeTab: initialTab
        )

        var effects = [Effect<MainViewAction>]()
        
        return [
            // Forced PsiCash RefreshState. This ensures updated balance is shown
            // even if the user is for example subscribed.
            environment.psiCashStore(.refreshPsiCashState(forced: true))
                .mapNever(),
            
            // Presents PsiCashViewController
            Effect.deferred {
                let topVC = environment.getTopActiveViewController()
                let searchResult = topVC.traversePresentingStackFor(type: PsiCashViewController.self)
                
                switch searchResult {
                case .notPresent:
                    let psiCashViewController = environment.makePsiCashViewController()
                    
                    topVC.present(psiCashViewController, animated: animated, completion: nil)
                    
                    return ._presentPsiCashScreenResult(willPresent: true)
                    
                case .presentInStack(_), .presentTopOfStack(_):
                    return ._presentPsiCashScreenResult(willPresent: false)
                }
            }
        ]
        
    case ._presentPsiCashScreenResult(willPresent: let willPresent):
        if !willPresent {
            state.mainView.psiCashViewState = .none
            return [
                environment.feedbackLogger.log(
                    .warn, "Will not present PsiCashViewController")
                    .mapNever()
            ]
        }
        return []

    case .dismissedPsiCashScreen:
        // If psiCashViewState is nil, it implies the PsiCashViewController not presented.
        guard case .some(_) = state.mainView.psiCashViewState else {
            return []
        }

        state.mainView.psiCashViewState = .none

        return []
        
    case .presentPsiCashAccountScreen:
        
        guard case .completed(false) = state.mainView.isPsiCashAccountScreenShown else {
            return []
        }
        
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

        state.mainView.isPsiCashAccountScreenShown = .pending
        
        return [
            Effect.deferred {
                let topVC = environment.getTopActiveViewController()
                let searchResult = topVC.traversePresentingStackFor(
                    type: PsiCashAccountViewController.self, searchChildren: true)
                
                switch searchResult {
                case .notPresent:
                    let accountsViewController = environment.makePsiCashAccountViewController()
                    topVC.present(accountsViewController, animated: true, completion: nil)
                    
                    return ._presentPsiCashAccountScreenResult(willPresent: true)
                    
                case .presentInStack(_), .presentTopOfStack(_):
                    return ._presentPsiCashAccountScreenResult(willPresent: false)
                }
            }
        ]
        
    case ._presentPsiCashAccountScreenResult(willPresent: let willPresent):
        state.mainView.isPsiCashAccountScreenShown = .completed(willPresent)
        if !willPresent {
            return [
                environment.feedbackLogger.log(
                    .warn, "Will not present PsiCash Accounts screen")
                    .mapNever()
            ]
        }
        return []
        
    case .dismissedPsiCashAccountScreen:

        state.mainView.isPsiCashAccountScreenShown = .completed(false)
        
        // if psiCashViewReducerState has value,then forwards
        // the PsiCash account dismissed event to psiCashViewReducer.
        switch state.psiCashViewReducerState {
        case .none:
            return []
        case .some(_):
            let effects = psiCashViewReducer(&state.psiCashViewReducerState!,
                                             .dismissedPsiCashAccountScreen,
                                             environment.psiCashViewEnvironment)
            
            return effects.map { $0.map { MainViewAction.psiCashViewAction($0) } }
        }
        
    case .presentSettingsScreen:
        
        guard case .completed(false) = state.mainView.isSettingsScreenShown else {
            return []
        }
        
        state.mainView.isSettingsScreenShown = .pending
        
        return [
            Effect.deferred {
                let topVC = environment.getTopActiveViewController()
                let searchResult = topVC.traversePresentingStackFor(
                    type: SettingsViewController.self, searchChildren: true)
                
                switch searchResult {
                case .notPresent:
                    let settingsViewController = environment.makeSettingsViewController()
                    topVC.present(settingsViewController, animated: true, completion: nil)
                    return ._presentSettingsScreenResult(willPresent: true)
                case .presentInStack(_), .presentTopOfStack(_):
                    return ._presentSettingsScreenResult(willPresent: false)
                }
            }
        ]
        
    case ._presentSettingsScreenResult(willPresent: let willPresent):
        state.mainView.isSettingsScreenShown = .completed(willPresent)
        if !willPresent {
            return [
                environment.feedbackLogger.log(
                    .warn, "Will not present settings screen")
                    .mapNever()
            ]
        }
        return []
        
    case .dismissedSettingsScreen(forceReconnect: let forceReconnect):
        state.mainView.isSettingsScreenShown = .completed(false)
        
        var effects = [Effect<MainViewAction>]()
        
        // Copies all settings, in case any setting has changed.
        effects += .fireAndForget {
            CopySettingsToPsiphonDataSharedDB.sharedInstance.copyAllSettings()
        }
        
        // Updates selected region, in case it has changed.
        effects += environment.serverRegionStore(.updateAvailableRegions)
            .mapNever()
        
        if forceReconnect {
            // Restarts VPN if settings have changed.
            effects += environment.tunnelIntentStore(.start(transition: .restart)).mapNever()
        }
        
        return effects
        
    case .presentModalFeedbackScreen:
        
        guard case .completed(false) = state.mainView.isModalFeedbackScreenShown else {
            return []
        }
        
        state.mainView.isModalFeedbackScreenShown = .pending
        
        return [
            Effect.deferred {
                let topVC = environment.getTopActiveViewController()
                let searchResult = topVC.traversePresentingStackFor(
                    type: FeedbackViewController.self, searchChildren: true)
                
                switch searchResult {
                case .notPresent:
                    let settingsViewController = environment.makeFeedbackViewController()
                    topVC.present(settingsViewController, animated: true, completion: nil)
                    return ._presentModalFeedbackScreenResult(willPresent: true)
                case .presentInStack(_), .presentTopOfStack(_):
                    return ._presentModalFeedbackScreenResult(willPresent: false)
                }
            }
        ]
        
    case ._presentModalFeedbackScreenResult(willPresent: let willPresent):
        
        state.mainView.isModalFeedbackScreenShown = .completed(willPresent)
        if !willPresent {
            return [
                environment.feedbackLogger.log(
                    .warn, "Will not present feedback screen")
                    .mapNever()
            ]
        }
        return []
        
    case .dismissedModalFeedbackScreen:
        
        guard state.mainView.isModalFeedbackScreenShown != .completed(false) else {
            // Feedback screen was not presented modally, instead
            // it was presented through PsiphonSettingsViewController.
            return []
        }
        
        state.mainView.isModalFeedbackScreenShown = .completed(false)
        return []
        
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
        uploadDiagnostics: Bool
    ) {
        
        let submitFeedbackData = SubmitFeedbackData(
            selectedThumbIndex: selectedThumbIndex,
            comments: comments ?? "",
            email: email ?? "",
            uploadDiagnostics: uploadDiagnostics
        )
        
        storeSend(.feedbackAction(.userSubmittedFeedback(submitFeedbackData)))
        
    }
    
    func userPressedURL(_ URL: URL!) {
        storeSend(.mainViewAction(.openExternalURL(URL)))
    }
    
    func feedbackViewControllerWillDismiss() {
        storeSend(.mainViewAction(.dismissedModalFeedbackScreen))
    }
    
}

/// `PsiphonSettingsDelegate` bridges callbacks from `PsiphonSettingsViewController`
/// to Store actions.
final class PsiphonSettingsDelegate: StoreDelegate<AppAction>, PsiphonSettingsViewControllerDelegate {
    
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
        storeSend(.mainViewAction(.dismissedSettingsScreen(forceReconnect: forceReconnect)))
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
        uploadDiagnostics: Bool
    ) {
        feedbackDelegate.userSubmittedFeedback(
            selectedThumbIndex, comments: comments, email: email, uploadDiagnostics: uploadDiagnostics)
    }
    
    func userPressedURL(_ URL: URL!) {
        feedbackDelegate.userPressedURL(URL)
    }
    
}
