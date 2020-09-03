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
import Utilities
import Promises

/// Represents different stages of onboarding.
/// Note that each stage may not be limited to only one screen.
enum OnboardingStage: String, Codable {
    case languageSelection
    case privacyPolicy_v2018_05_15
    case vpnConfigPermission
    case userNotificationPermission
    
    /// Ordered set of the stages that would have to be completed by the user.
    static let stagesToComplete: [OnboardingStage] =
        [ .languageSelection,
          .privacyPolicy_v2018_05_15,
          .vpnConfigPermission,
          .userNotificationPermission ]
    
    /// Returns ordered set of stages not completed by the user, given `completedStages`.
    static func findStagesNotCompleted(
        completedStages: [OnboardingStage]
    ) -> OrderedSet<OnboardingStage> {
        var stagesNotCompleted = OnboardingStage.stagesToComplete
        stagesNotCompleted.removeAll {
            completedStages.contains($0)
        }
        return OrderedSet(stagesNotCompleted)
    }
    
}

fileprivate extension OnboardingStage {
    
    var screens: OrderedSet<OnboardingScreen> {
        switch self {
        case .languageSelection,
             .privacyPolicy_v2018_05_15:
            return [ OnboardingScreen(stage: self, screenIndex: 0) ]
            
        case .vpnConfigPermission,
             .userNotificationPermission:
            return [ OnboardingScreen(stage: self, screenIndex: 0),
                     OnboardingScreen(stage: self, screenIndex: 1) ]
        }
    }
    
}

// TODO: Temporary struct for when tuples conform to Hashable.
fileprivate struct OnboardingScreen: Hashable {
    let stage: OnboardingStage
    let screenIndex: Int
}

fileprivate extension OnboardingScreen {
    
    var showNextButton: Bool {
        switch (self.stage, self.screenIndex) {
        case (.languageSelection, 0):
            return true
        case (.privacyPolicy_v2018_05_15, 0):
            return false
        case (.vpnConfigPermission, 0):
            return true
        case (.vpnConfigPermission, 1):
            return false
        case (.userNotificationPermission, 0):
            return true
        case (.userNotificationPermission, 1):
            return false
        default:
            fatalError("unknown value '\(self)'")
        }
    }
    
}

@objc final class OnboardingViewController: ReactiveViewController {
    
    /// Ordered set of onboarding stages.
    let onboardingStages: OrderedSet<OnboardingStage>
    
    /// Total number of screens given `onboardingStages`.
    let numberOfScreens: Int
    
    private let screens: OrderedSet<OnboardingScreen>
    private var currentScreenIndex: Int
    
    /// Convenience property to return current screen with index `currentScreenIndex`.
    fileprivate var currentScreen: OnboardingScreen {
        screens[currentScreenIndex]
    }
        
    // Views
    private var currentOnboardingView: UIView? = nil
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let nextButton = SwiftUIButton(type: .system)
    
    private let feedbackLogger: FeedbackLogger
    private let installVPNConfig: () -> Promise<VPNConfigInstallResult>
    private let onOnboardingFinished: (OnboardingViewController) -> Void

    init(
        onboardingStages: OrderedSet<OnboardingStage>,
        feedbackLogger: FeedbackLogger,
        installVPNConfig: @escaping () -> Promise<VPNConfigInstallResult>,
        onOnboardingFinished: @escaping (OnboardingViewController) -> Void
    ) {
        guard onboardingStages.count > 0 else {
            fatalError()
        }
        
        self.onboardingStages = onboardingStages
        self.numberOfScreens = onboardingStages.map(\.screens.count).reduce(0, +)
        
        self.screens = OrderedSet(onboardingStages.flatMap { $0.screens })
        self.currentScreenIndex = 0
        
        self.feedbackLogger = feedbackLogger
        self.installVPNConfig = installVPNConfig
        self.onOnboardingFinished = onOnboardingFinished
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setNeedsStatusBarAppearanceUpdate()
        
        self.view.backgroundColor = .darkBlue()
        
        // Adds background clouds
        let cloudsView = CloudsView(forAutoLayout: ())!
        self.view.addSubview(cloudsView)
        cloudsView.activateConstraints {
            $0.constraintToParentSafeArea(.top(0), .bottom(0), .leading(0), .trailing(0))
        }
        
        // Adds progress bar to the bottom of the screen
        self.view.addSubview(progressView)
        progressView.progressTintColor = .lightishBlue()
        progressView.activateConstraints {
            $0.constraintToParentSafeArea(.bottom(0), .leading(0), .trailing(0)) +
                [$0.heightAnchor.constraint(equalToConstant: 6.0)]
        }
        
        // Adds next button
        nextButton.setContentEdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 20)
        nextButton.setTitle(Strings.nextPageButtonTitle(), for: .normal)
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.titleLabel!.font = .avenirNextDemiBold(16.0)
        
        self.view.addSubview(nextButton)
        nextButton.activateConstraints {
            $0.constraintToParentSafeArea(.trailing(-20.0)) +
                [ $0.bottomAnchor.constraint(equalTo: progressView.topAnchor) ]
        }
        
        // Displays first screen.
        self.displayScreen(self.currentScreen)
    }
    
    /// Freezes next button, waiting for an async operation to finish.
    private func freezeOnboarding() {
        self.nextButton.isUserInteractionEnabled = false
    }
    
    /// Un-freezes next button so that actions can be taken.
    private func unfreezeOnboarding() {
        self.nextButton.isUserInteractionEnabled = true
    }
    
    private func gotoScreenFollowing(screenIndex: Int) {
        guard self.currentScreenIndex == screenIndex else {
            return
        }
        
        if self.screens[maybe: self.currentScreenIndex + 1] != nil {
            self.currentScreenIndex += 1
            self.displayScreen(self.currentScreen)
        } else {
            // Onboarding finished.
            self.onOnboardingFinished(self)
        }
    }
    
    /// Goes to the starting of the current onboarding stage.
    /// It is an error to call this method if current screen is already the starting screen of current index.
    private func gotoStartOfCurrentStage() {
        guard self.currentScreen.screenIndex > 0 else {
            // Already at the start of the current stage.
            fatalError()
        }
        
        self.currentScreenIndex -= 1
        self.displayScreen(self.currentScreen)
    }
    
    private func displayScreen(_ screen: OnboardingScreen) {
        
        let currentIndex = self.currentScreenIndex
        let onboardingView: UIView
        
        switch (screen.stage, screen.screenIndex) {
        case (.languageSelection, 0):
            onboardingView = makeLanguageSelectionOnboardingView { [unowned self] in
                let langSelectionViewController =
                    LanguageSelectionViewController(supportedLanguages: ())
                
                langSelectionViewController.selectionHandler = { _, _, viewController in
                    viewController.dismiss(animated: true, completion: nil)
                    // Reload the onboarding to reflect the newly selected language.
                    AppDelegate.shared().reloadOnboardingViewController()
                }
                
                let nav = UINavigationController(rootViewController: langSelectionViewController)
                self.present(nav, animated: true, completion: nil)
            }

        case (.privacyPolicy_v2018_05_15, 0):
            onboardingView = makePrivacyPolicyOnboardingView(
                onAccepted: { [unowned self] in
                    self.gotoScreenFollowing(screenIndex: currentIndex)
                },
                onDeclined: { [unowned self] in
                    let alert = makePrivacyPolicyDeclinedAlert()
                    self.present(alert, animated: true, completion: nil)
                }
            )

        case (.vpnConfigPermission, 0):
            onboardingView = OnboardingView(
                image: UIImage(named: "OnboardingVPNPermission")!,
                withTitle: Strings.onboardingGettingStartedHeaderText(),
                withBody: Strings.onboardingGettingStartedBodyText(),
                withAccessoryView: nil
            )
            
        case (.vpnConfigPermission, 1):
            onboardingView = makeVPNConfigPermissionGuideOnboardingView()
            
        case (.userNotificationPermission, _):
            onboardingView = OnboardingView(
                image: UIImage(named: "OnboardingPushNotificationPermission")!,
                withTitle: UserStrings.Onboarding_user_notification_permission_title(),
                withBody: UserStrings.Onboarding_user_notification_permission_body(),
                withAccessoryView: nil
            )
            
        default:
            fatalError("Unknown onboarding screen '\(screen)'")
        }
        
        self.updateView(onboardingView: onboardingView)
        
        // Updates `nextButton` event handler.
        nextButton.setEventHandler { [unowned self] in
            self.gotoScreenFollowing(screenIndex: currentIndex)
        }
        
        // Carries out any effects based on which screen is presented.
        
        switch screen {
        case OnboardingScreen(stage: .vpnConfigPermission, screenIndex: 1):
            
            self.freezeOnboarding()
            
            self.installVPNConfig().then { [unowned self] vpnConfigInstallResult in
                if Debugging.mainThreadChecks {
                    precondition(Thread.isMainThread, "action not called on main thread")
                }
                
                self.unfreezeOnboarding()
                
                switch vpnConfigInstallResult {
                case .installedSuccessfully:
                    // Go to next onboarding screen.
                    self.gotoScreenFollowing(screenIndex: currentIndex)
                
                case .permissionDenied:
                    // Re-start VPN config permission onboarding stage.
                    self.gotoStartOfCurrentStage()
                    
                    // Presents VPN permission denied alert.
                    let alert = AlertDialogs.vpnPermissionDeniedAlert()
                    self.present(alert, animated: true, completion: nil)
                    
                case .otherError:
                    // Re-start VPN config permission onboarding stage.
                    self.gotoStartOfCurrentStage()
                    
                    // Presents generic operation failed alert
                    let alert = AlertDialogs.genericOperationFailedTryAgain()
                    self.present(alert, animated: true, completion: nil)
                }
            }
            
        case OnboardingScreen(stage: .userNotificationPermission, screenIndex: 1):
            let centre = UNUserNotificationCenter.current()
            centre.getNotificationSettings { settings in
                guard settings.authorizationStatus == .notDetermined else {
                    DispatchQueue.main.async {
                        self.gotoScreenFollowing(screenIndex: currentIndex)
                    }
                    return
                }
                
                centre.requestAuthorization(options: [.alert, .badge]) { granted, maybeError in
                    self.feedbackLogger.immediate(
                        .info, "UserNotification authorization granted: \(granted)")
                    
                    if let error = maybeError {
                        self.feedbackLogger.immediate(
                            .error, "user notification authorization error: '\(error)'")
                    }
                    
                    DispatchQueue.main.async {
                        self.gotoScreenFollowing(screenIndex: currentIndex)
                    }
                }
            }
            
        default:
            // No effects
            break
        }

    }
    
    private func updateView(onboardingView: UIView) {
        progressView.progress = Float(self.currentScreenIndex + 1) / Float(numberOfScreens)
        
        nextButton.isHidden = !currentScreen.showNextButton
        
        self.currentOnboardingView?.removeFromSuperview()
        self.currentOnboardingView = onboardingView
        self.view.addSubview(onboardingView)
        
        let bottomConstraint: NSLayoutConstraint
        if !nextButton.isHidden {
            bottomConstraint = onboardingView.bottomAnchor
                .constraint(equalTo: self.nextButton.topAnchor)
        } else {
            bottomConstraint = onboardingView.bottomAnchor
                .constraint(equalTo: self.progressView.topAnchor, constant: -20.0)
        }
        
        onboardingView.activateConstraints {
            $0.constraintToParentSafeArea(.top(15.0), .centerX(0), .leading(0), .trailing(0)) +
                [   // Max width for large screens
                    $0.widthAnchor .constraint(lessThanOrEqualToConstant: 500.0),
                    bottomConstraint
                ]
        }
        
    }
    
}

// MARK: View helper functions

fileprivate func makeLanguageSelectionOnboardingView(
    onLanguageSelected: @escaping () -> Void
) -> OnboardingView {
    let selectLangButton = RingSkyButton(forAutoLayout: ())
    selectLangButton.includeChevron = true
    selectLangButton.setTitle(Strings.onboardingSelectLanguageButtonTitle())
    
    selectLangButton.setEventHandler(onLanguageSelected)
    
    return OnboardingView(
        image: UIImage(named: "OnboardingStairs")!,
        withTitle: Strings.onboardingBeyondBordersHeaderText(),
        withBody: Strings.onboardingBeyondBordersBodyText(),
        withAccessoryView: selectLangButton
    )
}

fileprivate func makePrivacyPolicyOnboardingView(
    onAccepted: @escaping () -> Void,
    onDeclined: @escaping () -> Void
) -> OnboardingScrollableView {
    let acceptButton = RoyalSkyButton(forAutoLayout: ())
    acceptButton.setTitle(UserStrings.Accept_button_title())
    acceptButton.shadow = true
    acceptButton.setEventHandler(onAccepted)
    
    let declineButton = RingSkyButton(forAutoLayout: ())
    declineButton.setTitle(UserStrings.Decline_button_title())
    declineButton.setEventHandler(onDeclined)
    
    let stackView = UIStackView(arrangedSubviews: [declineButton, acceptButton])
    stackView.spacing = 20.0
    stackView.distribution = .fillEqually
    
    return OnboardingScrollableView(
        image: UIImage(named: "OnboardingPrivacyPolicy")!,
        withTitle: Strings.privacyPolicyTitle(),
        withBody: Strings.privacyPolicyHTMLText_v2018(),
        withAccessoryView: stackView
    )
}

fileprivate func makePrivacyPolicyDeclinedAlert() -> UIAlertController {
    let alertController = UIAlertController(
        title: Strings.privacyPolicyTitle(),
        message: Strings.privacyPolicyDeclinedAlertBody(),
        preferredStyle: .alert
    )
    alertController.addAction(
        UIAlertAction(title: UserStrings.Dismiss_button_title(), style: .cancel)
    )
    return alertController
}

/// Creates view with an arrow pointing to "Allow" button of permission dialog.
/// The X and Y centre of the returned view is expected to match the X and Y centre of the screen.
fileprivate func makeVPNConfigPermissionGuideOnboardingView() -> UIView {
    let view = UIView()
    let arrowImage = UIImage(named: "PermissionArrow")!
    let arrowView = UIImageView(image: arrowImage)
    let label = UILabel.make(text: Strings.vpnInstallGuideText(),
                             fontSize: .h3,
                             typeface: .medium,
                             color: .white,
                             numberOfLines: 0,
                             alignment: .center)
    
    view.addSubviews(arrowView, label)
    
    let aspectRatio = arrowImage.size.width / arrowImage.size.height
    
    arrowView.activateConstraints {
        $0.constraint(to: view, .centerX(-60.0), .centerY(160.0)) +
            [ $0.heightAnchor.constraint(equalToConstant: 84.0),
              $0.widthAnchor.constraint(equalTo: $0.heightAnchor, multiplier: aspectRatio) ]
    }
    
    label.activateConstraints {
        $0.constraint(to: view, .centerX(0), .leading(0), .trailing(0)) +
            [ $0.topAnchor.constraint(equalTo: arrowView.bottomAnchor, constant: 10.0) ]
    }
    
    return view
}
