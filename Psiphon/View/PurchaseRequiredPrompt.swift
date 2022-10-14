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

import UIKit
import Utilities
import PsiApi
import enum AppStoreIAP.SubscriptionStatus
import struct PsiCashClient.PsiCashState

struct PurchaseRequiredPrompt: ViewBuilder {
    
    let subscribeButtonHandler: () -> Void
    let speedBoostButtonHandler: () -> Void
    let disconnectButtonHandler: () -> Void
    
    func build(_ container: UIView?) -> ImmutableBindableViewable<Utilities.Unit, UIView> {
        let background = UIView(frame: .zero)
        
        let backgroundImage = UIImageView.make(image: "PurchaseRequired")

        let title = UILabel.make(
            text: UserStrings.Psiphon_is_no_longer_free_in_your_region_title(),
            fontSize: .h3,
            typeface: .bold,
            color: .white,
            numberOfLines: 0,
            alignment: .center
        )
        
        let explanation = UILabel.make(
            text: UserStrings.Psiphon_is_no_longer_free_in_your_region_buy_sub_or_speedboost_body(),
            fontSize: .normal,
            typeface: .medium,
            color: .white,
            numberOfLines: 0,
            alignment: .center
        )
        
        let subscribeButton = GradientButton(contentShadow: true, gradient: .blue)
        mutate(subscribeButton) {
            $0.titleLabel!.apply(fontSize: .h3,
                                 typeface: .demiBold)
            $0.setTitleColor(.white, for: .normal)
            $0.setTitle(UserStrings.Subscribe_action_button_title(), for: .normal)
            $0.setEventHandler(self.subscribeButtonHandler)
        }
        
        let speedBoostButton = GradientButton(contentShadow: true, gradient: .blue)
        mutate(speedBoostButton) {
            $0.titleLabel!.apply(fontSize: .h3,
                                 typeface: .demiBold)
            $0.setTitleColor(.white, for: .normal)
            $0.setTitle(UserStrings.Speed_boost(), for: .normal)
            $0.setEventHandler(self.speedBoostButtonHandler)
        }
        
        let disconnectButton = GradientButton(contentShadow: false, gradient: .pureWhite)
        mutate(disconnectButton) {
            $0.setTitle(UserStrings.Vpn_disconnect_button_title(), for: .normal)
            $0.setTitleColor(UIColor.lightRoyalBlue(), for: .normal)
            $0.titleLabel!.apply(fontSize: .normal,
                                 typeface: .demiBold)
            $0.setEventHandler(self.disconnectButtonHandler)
        }
        
        // Add subviews
        background.addSubviews(
            title,
            explanation,
            subscribeButton,
            speedBoostButton,
            disconnectButton,
            backgroundImage
        )

        // Auto Layout
        
        title.activateConstraints {
            $0.constraintToParent(
                .width(const:0, multiplier: 0.8),
                .centerX(),
                .top(Float(Style.default.largePadding)))
        }
        
        explanation.activateConstraints {
            $0.constraintToParent(.centerX()) +
            [
                $0.topAnchor.constraint(equalTo: title.bottomAnchor,
                                        constant: Style.default.largePadding),
                $0.widthAnchor.constraint(equalTo: title.widthAnchor)
            ]
        }
        
        subscribeButton.activateConstraints {
            $0.constraintToParent(.centerX()) +
            [
                $0.topAnchor.constraint(equalTo: explanation.bottomAnchor,
                                        constant: Style.default.largePadding),
                $0.heightAnchor.constraint(equalToConstant: Style.default.buttonHeight),
                $0.widthAnchor.constraint(equalTo: title.widthAnchor)
            ]
        }
        
        speedBoostButton.activateConstraints {
            $0.constraintToParent(.centerX()) +
            [
                $0.topAnchor.constraint(equalTo: subscribeButton.bottomAnchor,
                                        constant: Style.default.largePadding),
                $0.heightAnchor.constraint(equalToConstant: Style.default.buttonHeight),
                $0.widthAnchor.constraint(equalTo: title.widthAnchor)
            ]
        }
        
        disconnectButton.activateConstraints {
            $0.constraintToParent(.centerX()) +
            [
                $0.topAnchor.constraint(equalTo: speedBoostButton.bottomAnchor,
                                        constant: Style.default.largePadding),
                $0.heightAnchor.constraint(equalToConstant: Style.default.buttonHeight),
                $0.widthAnchor.constraint(equalTo: title.widthAnchor)
            ]
        }
        
        backgroundImage.activateConstraints {
            $0.constraintToParent(.bottom(), .width()) +
            [
                $0.topAnchor.constraint(equalTo: disconnectButton.bottomAnchor,
                                        constant: Style.default.largePadding)
            ]
        }

        return .init(viewable: background) { _ -> ((Utilities.Unit) -> Void) in
            return { _ in }
        }
    }
    
}
