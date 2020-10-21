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
import UIKit
import PsiApi
import Utilities
import PsiCashClient
import SafariServices
import ReactiveSwift

final class PsiCashAccountViewController: ReactiveViewController {
    
    struct ReaderState: Equatable {
        let accountType: PsiCashAccountType?
        let pendingAccountLoginLogout: PsiCashState.PendingAccountLoginLogoutEvent
    }
    
    private struct ObservedState: Equatable {
        let readerState: ReaderState
        let lifeCycle: ViewControllerLifeCycle
        let navigation: NavigationState<PresentedScreen>
    }
    
    /// Represents view controller presented by PsiCashAuthViewController.
    enum PresentedScreen: Equatable {
        case createNewAccount
        case forgotPassword
    }
    
    private let store: Store<ReaderState, PsiCashAction>
    
    private let feedbackLogger: FeedbackLogger
    private let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    private let createNewAccountURL: URL
    private let forgotPasswordURL: URL
    private let loginOnly: Bool
    
    private let backgroundColour = UIColor.darkBlue()
    private let divider = DividerView(colour: .white(withAlpha: 0.25))
    private let createNewAccountButton = GradientButton(gradient: .grey)
    private let usernameTextField: SkyTextField<UITextField>
    private let passwordTextField: SkyTextField<SecretValueTextField>
    private let loginButtonSpinner: UIActivityIndicatorView
    private let loginButton: GradientButton
    
    private var controls = [UIControl]()
    
    /// Nil implies that no view controllers are presented.
    @State private var navigation: NavigationState<PresentedScreen> = .pending(.mainScreen)
    private var lastLoginLogoutEventDate: Date? = nil
    
    private let (lifetime, token) = Lifetime.make()
    

    init(
        store: Store<ReaderState, PsiCashAction>,
        feedbackLogger: FeedbackLogger,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        createNewAccountURL: URL,
        forgotPasswordURL: URL,
        loginOnly: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        
        self.feedbackLogger = feedbackLogger
        self.createNewAccountURL = createNewAccountURL
        self.forgotPasswordURL = forgotPasswordURL
        
        self.loginOnly = loginOnly
        self.usernameTextField = SkyTextField(placeHolder: UserStrings.Username())
        self.passwordTextField = SkyTextField(placeHolder: UserStrings.Password())
        self.loginButtonSpinner = .init(style: .gray)
        self.loginButton = GradientButton(gradient: .grey)
        
        self.tunnelConnectionRefSignal = tunnelConnectionRefSignal
        
        super.init(onDismiss: onDismiss)
        
        self.lifetime += SignalProducer.combineLatest(
            store.$value.signalProducer,
            self.$lifeCycle.signalProducer,
            self.$navigation.signalProducer
        ).map(ObservedState.init)
        .skipRepeats()
        .filter { observed in
            observed.lifeCycle.viewDidLoadOrAppeared
        }
        .startWithValues { [unowned self] observed in
            
            if Debugging.mainThreadChecks {
                guard Thread.isMainThread else {
                    fatalError()
                }
            }
            
            // Even though the reactive signal has a filter on
            // `!observed.lifeCycle.viewWillOrDidDisappear`, due to async nature
            // of the signal it is ambiguous if this closure is called when
            // `self.lifeCycle.viewWillOrDidDisappear` is true.
            // Due to this race-condition, the source-of-truth (`self.lifeCycle`),
            // is checked for whether view will or did disappear.
            guard !self.lifeCycle.viewWillOrDidDisappear else {
                return
            }

            guard let viewControllerDidLoadDate = self.viewControllerDidLoadDate else {
                fatalError()
            }
            
            if self.lastLoginLogoutEventDate == nil {
                self.lastLoginLogoutEventDate = viewControllerDidLoadDate
            }
            
            switch observed.readerState.pendingAccountLoginLogout {
            case .none:
                self.updateNoPendingLoginEvent()
                return
            
            case .some(let pendingAccountLoginEvent):

                defer {
                    self.lastLoginLogoutEventDate = pendingAccountLoginEvent.date
                }
                
                guard let lastLoginEventDate = self.lastLoginLogoutEventDate else {
                    fatalError()
                }
                
                switch pendingAccountLoginEvent.wrapped {
                case .pending(.login):
                    self.updatePendingLoginEvent()
                
                case .completed(.left(_)):
                    // Login event completed.
                    
                    guard pendingAccountLoginEvent.date > lastLoginEventDate else {
                        self.updateNoPendingLoginEvent()
                        return
                    }
                    
                    self.updateNoPendingLoginEvent()
                    
                case .pending(.logout), .completed(.right(_)):
                    // Dismisses current view controller if somehow the user
                    // is logging out.
                    let _ = self.display(screenToPresent: .parent)
                }
            }
        }
    }
    
    /// Updates the UI to a state where there is no pending login event.
    private func updateNoPendingLoginEvent() {
        self.controls.forEach { $0.isEnabled = true }
        self.loginButtonSpinner.isHidden = true
        self.loginButtonSpinner.stopAnimating()
        self.loginButton.setTitle(UserStrings.Log_in(), for: .normal)
    }
    
    /// Updates the UI to a state where all controls are disabled and a spinner is displayed.
    private func updatePendingLoginEvent() {
        self.controls.forEach { $0.isEnabled = false }
        self.loginButtonSpinner.isHidden = false
        self.loginButtonSpinner.startAnimating()
        self.loginButton.setTitle("", for: .normal)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let navigationController = self.navigationController else {
            fatalError()
        }
        
        self.navigation = .completed(.mainScreen)
        
        // Customize navigation controller
        
        mutate(navigationController.navigationBar) {
            $0.barStyle = .black
            $0.barTintColor = .darkBlue()
            $0.isTranslucent = false
            $0.titleTextAttributes = [
                NSAttributedString.Key.font:
                    UIFont.avenirNextMedium(CGFloat(FontSize.normal.rawValue)),
                NSAttributedString.Key.foregroundColor: UIColor.blueGrey()
            ]
            $0.hideSystemBottomBorder()
        }
        
        let navCancelBtn = UIBarButtonItem(title: "Cancel", style: .plain,
                                           target: self, action: #selector(onCancel))
        
        mutate(navCancelBtn) {
            $0.tintColor = .white
        }
        
        mutate(self.navigationItem) {
            $0.leftBarButtonItem = navCancelBtn
        }
        
        // Setup views
        let rootViewLayoutGuide = makeSafeAreaLayoutGuide(addToView: self.view)
        
        let paddedLayoutGuide = UILayoutGuide()
        view.addLayoutGuide(paddedLayoutGuide)
                
        paddedLayoutGuide.activateConstraints {
            $0.constraint(
                to: rootViewLayoutGuide,
                .top(Float(Style.default.padding)),
                .bottom(),
                .centerX()
            )
            +
            $0.widthAnchor.constraint(
                toDimension: rootViewLayoutGuide.widthAnchor,
                ratio: Style.default.layoutWidthToHeightRatio,
                max: Style.default.layoutMaxWidth
            )
        }
        
        let vStack = UIStackView.make(
            axis: .vertical,
            distribution: .fill,
            alignment: .fill,
            spacing: 15.0
        )
        
        let orTitle = ContainerView.makePaddingContainer(
            wraps: UILabel.make(
                text: UserStrings.Or(),
                fontSize: .normal,
                typeface: .demiBold,
                color: .white(withAlpha: 0.8),
                alignment: .center
            ),
            backgroundColor: self.backgroundColour,
            padding: Padding(top: 0, bottom: 0, leading: 10, trailing: 10)
        )
        
        mutate(createNewAccountButton) {
            $0.setTitleColor(.darkBlue(), for: .normal)
            
            $0.titleLabel!.apply(fontSize: .h3,
                                 typeface: .demiBold,
                                 color: .darkBlue())
            
            $0.setTitle(UserStrings.Create_new_account_button_title(), for: .normal)
            
            $0.contentEdgeInsets = Style.default.buttonMinimumContentEdgeInsets
        }
        
        mutate(usernameTextField.textField) {
            $0.becomeFirstResponder()
            $0.autocorrectionType = .no
            $0.autocapitalizationType = .none
            $0.returnKeyType = .next
        }
        
        mutate(passwordTextField.textField) {
            $0.returnKeyType = .go
        }
        
        mutate(usernameTextField.textField, passwordTextField.textField) {
            $0.delegate = self
            $0.clearButtonMode = .whileEditing
        }
        
        let forgotPasswordButton = UIButton()
        mutate(forgotPasswordButton) {
            $0.setTitle(UserStrings.Forgot_password_button_title(), for: .normal)
            $0.setTitleColor(.white, for: .normal)
            $0.titleLabel!.apply(fontSize: .normal,
                                 typeface: .medium,
                                 color: .white)
            $0.addTarget(self, action: #selector(onForgotPassword), for: .touchUpInside)
        }
        
        forgotPasswordButton.isHidden = true
        
        
        mutate(loginButton) {
            $0.setTitleColor(.darkBlue(), for: .normal)
            
            $0.titleLabel!.apply(fontSize: .h3,
                                 typeface: .demiBold,
                                 color: .darkBlue())
            
            $0.setTitle(UserStrings.Log_in(), for: .normal)
            
            $0.contentEdgeInsets = Style.default.buttonMinimumContentEdgeInsets
        }
        
        self.loginButtonSpinner.isHidden = true
        
        // Adds subviews
        self.loginButton.addSubview(self.loginButtonSpinner)
        
        mutate(self.view) {
            $0.backgroundColor = self.backgroundColour
            $0.addSubviews(vStack)
        }
        
        vStack.addArrangedSubviews(
            createNewAccountButton,
            divider,
            usernameTextField,
            passwordTextField,
            forgotPasswordButton,
            loginButton
        )
        
        vStack.addSubview(orTitle)
        
        orTitle.activateConstraints {
            $0.constraint(to: divider, .centerX(), .centerY())
        }
        
        vStack.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .top(), .leading(), .trailing())
        }
        
        createNewAccountButton.activateConstraints {
            $0.heightAnchor.constraint(default: Style.default.buttonHeight, max: nil)
        }
        
        loginButton.activateConstraints {
            $0.heightAnchor.constraint(default: Style.default.buttonHeight, max: nil)
        }
        
        self.loginButtonSpinner.activateConstraints {
            $0.constraint(to: loginButton, [.centerX(0), .centerY(0)])
        }
        
        createNewAccountButton.setEventHandler(self.onCreateNewAccount)
        loginButton.setEventHandler(self.onLogIn)

        // Sets UIControls variables
        self.controls = [
            createNewAccountButton,
            usernameTextField.textField,
            passwordTextField.textField,
            forgotPasswordButton,
            loginButton
        ]
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        mutate(self.createNewAccountButton, self.divider) {
            $0.isHidden = self.loginOnly
        }
    }
    
    @objc func onCreateNewAccount() {
        let _ = self.display(screenToPresent: .presented(.createNewAccount))
    }
    
    @objc func onCancel() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func onLogIn() {
        guard let username = self.usernameTextField.textField.text else {
            return
        }
        
        let password = self.passwordTextField.textField.secretText
        
        guard !username.isEmpty && !password.isEmpty else {
            return
        }
        
        self.store.send(
            .accountLogin(username: username, password: password))
    }
    
    @objc func onForgotPassword() {
    }

    // TODO: Can this be applied more generally to other view controllers?
    /// - Implementation limitation: Note that `display(screenToPresent:)` cannot be called in a
    /// signal that also observed `self.navigation` state observable. This will cause a recursive lock crash.
    private func display(screenToPresent: Navigation<PresentedScreen>) -> Bool {
        
        // Can only navigate to a new screen from the main screen,
        // otherwise what should be presented is not well-defined.
        
        guard case .completed(let currentScreen) = self.navigation else {
            // Navigation is in a pending state.
            self.feedbackLogger.immediate(.warn, """
                requested: '\(screenToPresent)'\
                : navigation is in a pending state: '\(self.navigation)'
                """)
            return false
        }
        
        guard currentScreen != screenToPresent else {
            // Already presenting `screen`.
            return true
        }
        
        switch (currentScreen: currentScreen, screenToPresent: screenToPresent) {
        case (currentScreen: .presented(_), screenToPresent: .mainScreen):
            
            // Dismisses the presented view controller.
            guard let presentedViewController = self.presentedViewController else {
                // There is no presentation to dismiss.
                return true
            }

            self.navigation = .pending(.mainScreen)
            
            UIViewController.safeDismiss(presentedViewController, animated: true) {
                self.navigation = .completed(.mainScreen)
            }

            return true
            
        case (currentScreen: .mainScreen, screenToPresent: .parent):
            self.navigation = .pending(.parent)
            self.dismiss(animated: true) {
                self.navigation = .completed(.parent)
            }
            return true
            
        case (currentScreen: .mainScreen, screenToPresent: .presented(let screenToPresent)):
            // Note that presenting a view controller is only well-defined
            // if the current screen is the main screen.
            
            // Last second check for tunnel connection status for screens that open the browser.
            switch screenToPresent{
            case .createNewAccount, .forgotPassword:
                guard
                    case .success(let tunnelConnection) = self.tunnelConnectionRefSignal.first(),
                    case .connected = tunnelConnection?.tunneled
                else {
                    // TODO: Alerts are not represented in the navigation state.
                    //       is there a way to combine error alerts like this?
                    self.displayBasicErrorAlert(
                        errorDesc: ErrorEventDescription<ErrorRepr>(
                            event: .init(ErrorRepr(repr: "tunnel not connected"), date: Date()),
                            localizedUserDescription: UserStrings.Psiphon_is_not_connected()))
                    
                    self.feedbackLogger.immediate(.warn, "tunnel not connected")
                    return false
                }
            }
            
            let viewControllerToPresent = self.makeViewController(screen: screenToPresent)
            let success = self.safePresent(viewControllerToPresent, animated: true) {
                // Finished presenting view controller.
                self.navigation = .completed(.presented(screenToPresent))
            }
            
            if success {
                self.navigation = .pending(.presented(screenToPresent))
                return true
            } else {
                return false
            }
        
        default:
            self.feedbackLogger.immediate(.error, """
                cannot navigate from '\(currentScreen)' to '\(screenToPresent)'
                """)
            return false
        }
    }
    
    private func makeViewController(screen: PresentedScreen) -> UIViewController {
        let url: URL
        switch screen {
        case .createNewAccount:
            url = self.createNewAccountURL
        case .forgotPassword:
            url = self.forgotPasswordURL
        }
        
        let safari = SFSafariViewController(url: url)
        safari.delegate = self
        
        return safari
    }
    
}

extension PsiCashAccountViewController: UITextFieldDelegate {
    
    @objc func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if self.usernameTextField.textField === textField {
            // Selects next field (password field) for text input.
            self.usernameTextField.textField.resignFirstResponder()
            self.passwordTextField.textField.becomeFirstResponder()

        } else if self.passwordTextField.textField === textField {
            self.passwordTextField.textField.resignFirstResponder()
            self.onLogIn()
        }
        
        return true
    }
    
}

extension PsiCashAccountViewController: SFSafariViewControllerDelegate {
    
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        let _ = self.display(screenToPresent: .mainScreen)
    }
    
}
