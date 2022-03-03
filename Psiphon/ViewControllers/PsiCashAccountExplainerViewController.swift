/*
 * Copyright (c) 2022, Psiphon Inc.
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
import ReactiveSwift

/// Contains an explainer of PsiCash accounts and two buttons that allow the user
/// to either create a new PsiCash account or log into their existing account.
final class PsiCashAccountExplainerViewController: ReactiveViewController {
    
    private let feedbackLogger: FeedbackLogger
    private let createNewAccountURL: URL
    private let learnMorePsiCashAccountURL: URL
    private let psiCashStore: Store<Utilities.Unit, PsiCashAction>
    private let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    private let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>

    private let makePsiCashAccountLoginViewController: () -> PsiCashAccountLoginViewController
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(
        makePsiCashAccountLoginViewController: @escaping () -> PsiCashAccountLoginViewController,
        createNewAccountURL: URL,
        learnMorePsiCashAccountURL: URL,
        psiCashStore: Store<Utilities.Unit, PsiCashAction>,
        tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        feedbackLogger: FeedbackLogger
    ) {
        self.makePsiCashAccountLoginViewController = makePsiCashAccountLoginViewController
        self.createNewAccountURL = createNewAccountURL
        self.learnMorePsiCashAccountURL = learnMorePsiCashAccountURL
        self.psiCashStore = psiCashStore
        self.tunnelStatusSignal = tunnelStatusSignal
        self.tunnelConnectionRefSignal = tunnelConnectionRefSignal
        self.feedbackLogger = feedbackLogger
        
        super.init(onDidLoad: nil, onDismissed: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let _ = self.navigationController else {
            fatalError()
        }
        
        self.title = UserStrings.Psicash_account()
        
        // Adds cancel nav bar button.
        let navCancelBtn = UIBarButtonItem(title: UserStrings.Cancel_button_title(),
                                           style: .plain,
                                           target: self, action: #selector(onCancel))
        self.navigationItem.leftBarButtonItem = navCancelBtn
        
        // Back button when this view controller is just below topmost view controller.
        let backBtn = UIBarButtonItem()
        backBtn.title = UserStrings.Back_button_title()
        self.navigationItem.backBarButtonItem = backBtn
        
        // Setup views
        let rootViewLayoutGuide = makeSafeAreaLayoutGuide(addToView: self.view)
        
        let paddedLayoutGuide = UILayoutGuide()
        view.addLayoutGuide(paddedLayoutGuide)
                
        paddedLayoutGuide.activateConstraints {
            $0.constraint(
                to: rootViewLayoutGuide,
                .top(Float(Style.default.padding)),
                .bottom(Float(-Style.default.padding)),
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
        
        let image = UIImageView.make(
            image: "PsiCashGuard",
            contentMode: .scaleAspectFit,
            easyToShrink: false
        )
        
        let title = UILabel.make(
            text: UserStrings.Protect_your_psicash_title(),
            fontSize: .h2,
            typeface: .bold,
            color: .white,
            alignment: .center
        )

        let createAcctBtn = GradientButton(shadow: .none,
                                          contentShadow: false,
                                          gradient: .blue)
        mutate(createAcctBtn) {
            $0.setTitle(UserStrings.Create_account_button_title(), for: .normal)
            $0.setTitleColor(.white, for: .normal)
            $0.titleLabel?.font = UIFont.avenirNextBold(CGFloat(FontSize.normal.rawValue))
            $0.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            $0.setEventHandler(self.onSignUpButtonTapped)
        }
        
        
        let accountsExplainer =  UILabel.make(
            text: UserStrings.Psicash_account_explainer_text(),
            fontSize: .normal,
            typeface: .medium,
            color: .white,
            numberOfLines: 0,
            alignment: .natural
        )
        
        let learnMoreBtn = SwiftUIButton()
        mutate(learnMoreBtn) {
            $0.setTitle(UserStrings.Learn_more_title(), for: .normal)
            $0.setTitleColor(.white, for: .normal)
            $0.titleLabel!.apply(fontSize: .normal,
                                 typeface: .bold)
            $0.setEventHandler(self.onLearnMoreTapped)
        }
        
        let alreadyHaveAccountTitle = UILabel.make(
            text: UserStrings.Already_have_an_account(),
            fontSize: .h2,
            typeface: .bold,
            color: .white,
            alignment: .center
        )
        
        let logInButton = GradientButton(shadow: .none,
                                         contentShadow: false,
                                         gradient: .grey)
        mutate(logInButton) {
            $0.setTitle(UserStrings.Log_in(), for: .normal)
            $0.setTitleColor(.darkBlue(), for: .normal)
            $0.titleLabel?.font = UIFont.avenirNextBold(CGFloat(FontSize.normal.rawValue))
            $0.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            $0.setEventHandler(self.onLogInButtonTapped)
        }
        
        // Adds subviews
        mutate(self.view) {
            $0.backgroundColor = Style.default.defaultBackgroundColor
            $0.addSubviews(vStack)
        }
        
        vStack.addArrangedSubviews(
            image,
            title,
            createAcctBtn,
            accountsExplainer,
            learnMoreBtn,
            SpacerView(.flexible),
            alreadyHaveAccountTitle,
            logInButton
        )
        
        vStack.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .top(), .bottom(), .leading(), .trailing())
        }
        
        createAcctBtn.activateConstraints {
            $0.heightAnchor.constraint(default: Style.default.buttonHeight, max: nil)
        }
        
        logInButton.activateConstraints {
            $0.heightAnchor.constraint(default: Style.default.buttonHeight, max: nil)
        }
        
    }
    
    private func onSignUpButtonTapped() {
        let v = makeSignUpWebViewController()
        self.navigationController!.pushViewController(v, animated: true)
    }
    
    private func onLogInButtonTapped() {
        let v = makePsiCashAccountLoginViewController()
        self.navigationController!.pushViewController(v, animated: true)
    }
        
    @objc func onLearnMoreTapped() {
        let v = makeLearnMoreViewController()
        self.navigationController!.pushViewController(v, animated: true)
    }

    @objc func onCancel() {
        self.dismiss(animated: true, completion: nil)
    }
    
    private func makeLearnMoreViewController () -> UIViewController {
        
        let webViewViewController = WebViewController(
            baseURL: self.learnMorePsiCashAccountURL,
            feedbackLogger: self.feedbackLogger,
            tunnelStatusSignal: self.tunnelStatusSignal,
            tunnelProviderRefSignal: self.tunnelConnectionRefSignal,
            onDidLoad: nil,
            onDismissed: nil
        )
        
        webViewViewController.title = UserStrings.Psicash_account()
        
        return webViewViewController
        
    }
    
    private func makeSignUpWebViewController() -> UIViewController {
        
        let webViewViewController = WebViewController(
            baseURL: self.createNewAccountURL,
            feedbackLogger: self.feedbackLogger,
            tunnelStatusSignal: self.tunnelStatusSignal,
            tunnelProviderRefSignal: self.tunnelConnectionRefSignal,
            onDidLoad: nil,
            onDismissed: {
                
                // PsiCash RefreshState after dismissal of Account Management screen.
                // This is necessary since the user might have updated their username, or
                // other account information.
                self.psiCashStore.send(.refreshPsiCashState(forced: true))
                
            }
        )
        
        webViewViewController.title = UserStrings.Psicash_account()
        
        return webViewViewController
        
    }

    
}
