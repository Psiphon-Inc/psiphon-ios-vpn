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

final class PsiCashAccountSignupOrLoginView: UIView {
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let title: UILabel
    private let subtitle: UILabel
    private let button: GradientButton
    
    init() {
        
        title = UILabel.make(
            text: UserStrings.Psicash_account(),
            fontSize: .normal,
            typeface: .bold
        )
        
        subtitle = UILabel.make(
            text: UserStrings.Protect_your_purchases(),
            fontSize: .normal,
            typeface: .mediumItalic,
            numberOfLines: 0
        )
        
        button = GradientButton(shadow: .strong, contentShadow: false, gradient: .vividBlue)
        
        super.init(frame: .zero)
        
        // View properties
        addShadow(toLayer: layer)
        layer.cornerRadius = Style.default.cornerRadius
        backgroundColor = .white(withAlpha: 0.42)
        
        mutate(button) {
            $0.setTitle(UserStrings.Log_in_or_sign_up(), for: .normal)
            $0.setTitleColor(.white, for: .normal)
            $0.titleLabel?.font = UIFont.avenirNextBold(CGFloat(FontSize.normal.rawValue))
            $0.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        }
        
        // Adds subviews.
        addSubviews(title, subtitle, button)
        
        // Sets up AutoLayout.
        
        // Padding between both titles and the button.
        let titleButtonConstant = CGFloat(-10.0)
        
        title.activateConstraints {
            $0.constraintToParent(
                .leading(Float(Style.default.padding)),
                .top(Float(Style.default.padding))
            ) + [
                // Title should not overlap with the button
                $0.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor,
                                             constant: titleButtonConstant)
            ]
        }
        
        subtitle.activateConstraints {
            $0.constraintToParent(.bottom(Float(-Style.default.padding))) +
                $0.constraint(to: title, .leading()) +
                [
                    $0.topAnchor.constraint(equalTo: title.bottomAnchor),
                    // Subtitle should not overlap with the button
                    $0.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor,
                                                 constant: titleButtonConstant)
                ]
        }
        
        button.activateConstraints {
                $0.constraintToParent(
                    .centerY(0),
                    .trailing(Float(-Style.default.padding))
                )
                + [
                    // Set width to half of parent's width.
                    $0.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.45)
                ]
        }

    }
    
    func onLogInTapped(_ handler: @escaping () -> Void) {
        button.setEventHandler(handler)
    }
    
}
