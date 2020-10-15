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
import SafariServices

@objc final class PsiCashAuthViewController: ReactiveViewController, UITextFieldDelegate {
    
    private let feedbackLogger: FeedbackLogger
    private let createNewAccountURL: URL
    private let forgotPasswordURL: URL
    
    private let backgroundColour = UIColor.darkBlue()
    private let loginOnly: Bool
    private let divider = DividerView(colour: .white(withAlpha: 0.25))
    private let createNewAccountButton = GradientButton(gradient: .grey)
    private let usernameTextField: SkyTextField<UITextField>
    private let passwordTextField: SkyTextField<SecretValueTextField>
    
    init(
        feedbackLogger: FeedbackLogger,
        createNewAccountURL: URL,
        forgotPasswordURL: URL,
        loginOnly: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.feedbackLogger = feedbackLogger
        self.createNewAccountURL = createNewAccountURL
        self.forgotPasswordURL = forgotPasswordURL
        
        self.loginOnly = loginOnly
        self.usernameTextField = SkyTextField(placeHolder: UserStrings.Username())
        self.passwordTextField = SkyTextField(placeHolder: UserStrings.Password())
        super.init(onDismiss: onDismiss)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        
        guard let navigationController = self.navigationController else {
            fatalError()
        }
        
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
        
        let loginButton = GradientButton(gradient: .grey)
        mutate(loginButton) {
            $0.setTitleColor(.darkBlue(), for: .normal)
            
            $0.titleLabel!.apply(fontSize: .h3,
                                 typeface: .demiBold,
                                 color: .darkBlue())
            
            $0.setTitle(UserStrings.Log_in(), for: .normal)
            
            $0.contentEdgeInsets = Style.default.buttonMinimumContentEdgeInsets
        }
        
        // Adds subviews
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
        
        createNewAccountButton.setEventHandler(self.onCreateNewAccount)
        loginButton.setEventHandler(self.onLogIn)

    }
    
    override func viewWillAppear(_ animated: Bool) {
        mutate(self.createNewAccountButton, self.divider) {
            $0.isHidden = self.loginOnly
        }
    }
    
    @objc func onCreateNewAccount() {
        let safari = SFSafariViewController(url: self.createNewAccountURL)
        safari.delegate = self
        
        let success = safePresent(safari, animated: true)
        self.feedbackLogger.immediate(.info, "presented SFSafariViewController: '\(success)'")
    }
    
    @objc func onCancel() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func onLogIn() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func onForgotPassword() {
        
    }
    
    @objc func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if usernameTextField === textField {
            // Selects next field (password field) for text input.
            usernameTextField.resignFirstResponder()
            passwordTextField.becomeFirstResponder()

        } else if passwordTextField === textField {
            passwordTextField.resignFirstResponder()
            onLogIn()
        }
        
        return true
    }
    
}

extension PsiCashAuthViewController: SFSafariViewControllerDelegate {
    
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        UIViewController.safeDismiss(controller, animated: true, completion: nil)
    }
    
}
