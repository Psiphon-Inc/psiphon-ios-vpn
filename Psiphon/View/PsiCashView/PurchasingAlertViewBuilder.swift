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

struct PurchasingAlertViewBuilder: ViewBuilder {

    enum Alert: Equatable {
        case psiCash
        case speedBoost
    }

    let alert: Alert

    func build(_ container: UIView?) -> ImmutableBindableViewable<Utilities.Unit, UIView> {
        let background = UIView(frame: .zero)

        let vStack = UIStackView.make(
            axis: .vertical,
            distribution: .fill,
            alignment: .fill,
            spacing: Style.default.padding
        )

        let image: UIImageView

        let title = UILabel.make(fontSize: .h3,
                                 typeface: .bold,
                                 color: .blueGrey(),
                                 numberOfLines: 0,
                                 alignment: .center)

        switch alert {
        case .psiCash:
            image = UIImageView.make(image: "PsiCashCoin_Large")
            title.text = UserStrings.Purchasing_psiCash().localizedUppercase

        case .speedBoost:
            image = UIImageView.make(image: "RedRocket")
            title.text = UserStrings.Purchasing_speed_boost().localizedUppercase
        }

        // Add subviews
        background.addSubview(vStack)
        vStack.addArrangedSubviews(
            image,
            title
        )

        // Layout
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
