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

/// ObjC wrapper around `SubscriptionBarView.SubscriptionBarState`.
@objc final class ObjcSubscriptionBarViewState: NSObject {
    let state: SubscriptionBarView.BindingType
    
    init(swiftState state: SubscriptionBarView.BindingType) {
        self.state = state
    }
    
    /// Maps `SubscriptionBarView.SubscriptionBarState.backgroundGradientColors` to `[CGColor]`.
    /// However since this property is used from Objective-C, arrays are mapped to `NSArray`
    /// which can't hold primitive types. This is resolved by casting to `[Any]`.
    ///
    /// For example this is equivalent to `id` cast in ObjC: `@[(id)UIColor.someColor.CGColor, ...]`.
    @objc var backgroundGradientColors: [Any] {
        return self.state.backgroundGradientColors.cgColors
    }
    
}

@objc final class SubscriptionBarView: UIControl, Bindable {
    typealias BindingType = SubscriptionBarState
    
    struct SubscriptionBarState: Equatable {
        
        enum AuthState: Equatable {
            case notSubscribed
            case subscribedWithAuth
            case failedRetry
            case pending
        }
        
        let tunnelStatus: TunnelConnectedStatus
        let authState: AuthState
    }

    private let clickHandler: (SubscriptionBarState) -> Void
    private let manageButton: WhiteSkyButton
    private let statusView: SubscriptionStatusView
    private let hStackView: UIStackView
    private let statusViewContainer: UIView
    private let manageButtonContainer: UIView
    
    private var currentState = SubscriptionBarState(tunnelStatus: .notConnected,
                                                    authState: .notSubscribed)
        
    init(clickHandler: @escaping (SubscriptionBarState) -> Void) {
        self.clickHandler = clickHandler
        self.manageButton = WhiteSkyButton(forAutoLayout: ())
        self.statusView = SubscriptionStatusView()
        self.hStackView = UIStackView()
        self.statusViewContainer = UIView()
        self.manageButtonContainer = UIView()
        
        super.init(frame: .zero)
        self.addTarget(self, action: #selector(onClick), for: .touchUpInside)
        
        
        self.manageButton.shadow = true
        
        self.hStackView.axis = .horizontal
        self.hStackView.distribution = .fillEqually
        self.hStackView.isUserInteractionEnabled = false
        
        
        // Adds views
        
        self.addSubview(hStackView)
        
        self.statusViewContainer.addSubview(statusView)
        self.hStackView.addArrangedSubview(statusViewContainer)
        
        self.manageButtonContainer.addSubview(manageButton)
        self.hStackView.addArrangedSubview(manageButtonContainer)
        
        
        // Setsup autolayout
        
        self.hStackView.activateConstraints {
            $0.constraintToParent(
                .width(const: 0, multiplier: 0.9),
                .height(const: 0, multiplier: 1.0),
                .centerX(0),
                .centerY(0)
            )
        }

        self.statusView.activateConstraints {
            $0.constraintToParent(
                .width(const: 0, multiplier: 0.9),
                .height(const: 0, multiplier: 0.456),
                .centerX(0),
                .centerY(0)
            )
        }
        
        self.manageButton.activateConstraints {
            $0.constraintToParent(
                .width(const: 0, multiplier: 0.732),
                .height(const: 0, multiplier: 0.5),
                .centerX(0),
                .centerY(0)
            )
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func onClick() {
        self.clickHandler(self.currentState)
    }
    
    func bind(_ newValue: SubscriptionBarState) {
        self.currentState = newValue
        self.manageButton.isEnabled = newValue.subscriptionButtonEnabled
        
        UIView.transition(
            with: self.statusView,
            duration: Style.default.animationDuration,
            options: .transitionCrossDissolve,
            animations: {
                self.statusView.setTitle(newValue.localizedTitle)
                self.statusView.setSubtitle(newValue.localizedSubtitle)
                self.manageButton.setTitle(newValue.localizedSubscriptionButtonTitle)
        })
        
        UIView.animate(
            withDuration: Style.default.animationDuration,
            animations: {
                self.manageButton.titleLabel.textColor = newValue.subscriptionButtonColor
                self.manageButton.alpha = newValue.subscriptionButtonEnabled ? 1.0 : 0.0
        })
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if self.manageButton.isEnabled {
            self.manageButton.touchesBegan(touches, with: event)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if self.manageButton.isEnabled {
            self.manageButton.touchesEnded(touches, with: event)
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if self.manageButton.isEnabled {
            self.manageButton.touchesCancelled(touches, with: event)
        }
        
    }
    
}

extension SubscriptionBarView {
    
    @objc func objcBind(_ objcBindingValue: ObjcSubscriptionBarViewState) {
        self.bind(objcBindingValue.state)
    }
    
}

extension SubscriptionBarView.SubscriptionBarState {
    
    static func make(
        authState: SubscriptionAuthState,
        subscriptionStatus: SubscriptionStatus,
        tunnelStatus: TunnelConnectedStatus
    ) -> Self {
        switch subscriptionStatus {
        case .unknown, .notSubscribed:
            return .init(tunnelStatus: tunnelStatus, authState: .notSubscribed)
        
        case .subscribed(let subscriptionPurchase):
            guard let purchasesAuthState = authState.purchasesAuthState else {
                // purchasesAuthState will eventually match subscription
                // information presented by subscriptionStatus.
                // For now pretend that the state is not subscribed.
                return .init(tunnelStatus: tunnelStatus, authState: .notSubscribed)
            }
            
            let webOrderID = subscriptionPurchase.webOrderLineItemID
            guard let purchaseState = purchasesAuthState[webOrderID] else {
                return .init(tunnelStatus: tunnelStatus, authState: .notSubscribed)
            }
            
            if authState.transactionsPendingAuthRequest.contains(webOrderID) {
                return .init(tunnelStatus: tunnelStatus, authState: .pending)
            } else {
                
                switch purchaseState.signedAuthorization {
                case .authorization(_):
                    return .init(tunnelStatus: tunnelStatus, authState: .subscribedWithAuth)
                
                case .notRequested, .rejectedByPsiphon(_), .requestRejected(_):
                    return .init(tunnelStatus: tunnelStatus, authState: .notSubscribed)
                    
                case .requestError(_):
                    return .init(tunnelStatus: tunnelStatus, authState: .failedRetry)
                }

            }
        }
    }
    
    var backgroundGradientColors: [UIColor] {
        switch self.authState {
        case .notSubscribed, .subscribedWithAuth:
            return [.lightishBlue(), .lightRoyalBlueTwo()]
        case .pending, .failedRetry:
            if self.tunnelStatus == .connected {
                return [.lightBluishGreen(), .algaeGreen()]
            } else {
                return [.salmon(), .brightOrange()]
            }
        }
    }
    
    var localizedTitle: String {
        switch self.authState {
        case .notSubscribed:
            return UserStrings.Get_premium_header_not_subscribed()
        case .subscribedWithAuth, .failedRetry:
            return UserStrings.Subscription_bar_header()
        case .pending:
            switch self.tunnelStatus {
            case .connected:
                return UserStrings.Subscription_bar_header()
            case .connecting, .disconnecting, .notConnected:
                return UserStrings.Subscription_pending_bar_header()
            }
        }
    }
    
    var localizedSubtitle: String {
        switch self.authState {
        case .notSubscribed:
            return UserStrings.Remove_ads_max_speed_footer_not_subscribed()
        case .subscribedWithAuth:
            return UserStrings.Premium_max_speed_footer_subscribed()
        case .failedRetry:
            return UserStrings.Failed_to_activate_subscription()
        case .pending:
            switch self.tunnelStatus {
            case .notConnected:
                return UserStrings.Connect_to_activate_subscription()
            case .connected:
                return UserStrings.Please_wait_while_activating_subscription()
            case .connecting, .disconnecting:
                return ""
            }
        }
    }
    
    var localizedSubscriptionButtonTitle: String {
        switch self.authState {
        case .notSubscribed:
            return UserStrings.Subscribe_action_button_title()
        case .subscribedWithAuth:
            return UserStrings.Manage_subscription_button_title()
        case .failedRetry:
            return UserStrings.Retry_button_title()
        case .pending:
            switch self.tunnelStatus {
            case .notConnected:
                return UserStrings.Connect_button_title()
            case .connected:
                return UserStrings.Activating_subscription_title()
            case .connecting, .disconnecting:
                return ""
            }
        }
    }
    
    var subscriptionButtonColor: UIColor {
        switch self.authState {
        case .notSubscribed, .subscribedWithAuth:
            return .lightRoyalBlue()
        case .failedRetry:
            return .darkBlue()
        case .pending:
            if self.tunnelStatus == .connected {
                return .greyish()
            } else {
                return .darkBlue()
            }
        }
    }
    
    var subscriptionButtonEnabled: Bool {
        switch self.authState {
        case .notSubscribed, .subscribedWithAuth:return true
        case .failedRetry, .pending:
            switch self.tunnelStatus {
            case .connecting, .disconnecting: return false
            case .connected, .notConnected: return true
            }
        }
    }
    
}
