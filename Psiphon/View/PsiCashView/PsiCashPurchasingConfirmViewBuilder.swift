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

import UIKit
import Utilities

struct PsiCashPurchasingConfirmViewBuilder: ViewBuilder {
    
    let closeButtonHandler: () -> Void
    let signUpButtonHandler: () -> Void
    let continueWithoutAccountHandler: () -> Void
    
    func build(_ container: UIView?) -> ImmutableBindableViewable<Utilities.Unit, UIView> {
        let background = UIView(frame: .zero)
        
        let vStack = UIStackView.make(
            axis: .vertical,
            distribution: .fill,
            alignment: .fill,
            spacing: 20.0,
            margins: nil
        )

        let hStack = UIStackView.make(
            axis: .horizontal,
            distribution: .fill,
            alignment: .center,
            spacing: Style.default.padding,
            margins: nil
        )
        
        let largeCoinImage = UIImageView.make(image: "PsiCashCoin_Large")
        largeCoinImage.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal)

        let title = UILabel.make(
            text: UserStrings.Psicash_account(),
            fontSize: .h3,
            typeface: .bold,
            color: .blueGrey(),
            numberOfLines: 1,
            alignment: .center
        )
        
        let closeButton = CloseButton(frame: .zero)
        closeButton.setEventHandler(self.closeButtonHandler)
        
        let explanation = UILabel.make(
            text: UserStrings.Encourage_psicash_account_creation_body(),
            fontSize: .normal,
            typeface: .medium,
            color: .blueGrey(),
            numberOfLines: 0,
            alignment: .natural
        )
        
        let signUpButton = GradientButton(contentShadow: true, gradient: .blue)
        mutate(signUpButton) {
            $0.titleLabel!.apply(fontSize: .h3,
                                 typeface: .demiBold)
            $0.setTitleColor(.white, for: .normal)
            $0.setTitle(UserStrings.Create_or_log_into_account(), for: .normal)
            $0.setEventHandler(self.signUpButtonHandler)
        }
        
        let continueWithoutAccountButton = SwiftUIButton()
        mutate(continueWithoutAccountButton) {
            $0.setTitle(UserStrings.Continue_without_account(), for: .normal)
            $0.setTitleColor(.white, for: .normal)
            $0.titleLabel!.apply(fontSize: .normal,
                                 typeface: .medium,
                                 color: .white)
            $0.setEventHandler(self.continueWithoutAccountHandler)
        }
        
        // Add subviews
        background.addSubview(vStack)
        
        hStack.addArrangedSubviews(largeCoinImage, title, closeButton)
        
        vStack.addArrangedSubviews(
            hStack,
            explanation,
            signUpButton,
            continueWithoutAccountButton
        )

        // Auto Layout
        largeCoinImage.activateConstraints {
            $0.widthAnchor.constraint(toDimension: $0.heightAnchor)
        }

        signUpButton.activateConstraints {
            $0.heightAnchor.constraint(default: Style.default.buttonHeight)
        }

        vStack.activateConstraints {
            $0.constraintToParent(.centerX(), .centerY())
        }

        background.activateConstraints {
            [
                $0.widthAnchor.constraint(equalTo: vStack.widthAnchor,
                                          constant: 2 * Style.default.padding),
                $0.heightAnchor.constraint(equalTo: vStack.heightAnchor,
                                           constant: 2 * Style.default.largePadding)
            ]
        }

        return .init(viewable: background) { _ -> ((Utilities.Unit) -> Void) in
            return { _ in }
        }
    }
    
}
