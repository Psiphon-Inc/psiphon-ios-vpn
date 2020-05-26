/*
 * Copyright (c) 2019, Psiphon Inc.
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

struct PurchasingSpeedBoostAlertViewBuilder: ViewBuilder {

    let message = UserStrings.Purchasing_speed_boost()

    func build(_ container: UIView?) -> StrictBindableViewable<Utilities.Unit, UIView> {
        let background = UIView(frame: .zero)
        let stackView = UIStackView(frame: .zero)
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let image = UIImageView.make(image: "RedRocket")

        let title = UILabel.make(fontSize: .h3,
                                 typeface: .bold,
                                 color: .blueGrey(),
                                 numberOfLines: 0,
                                 alignment: .center)
        title.text = message.localizedUppercase

        // Add subviews
        background.addSubview(stackView)
        stackView.addArrangedSubview(image)
        stackView.addArrangedSubview(title)

        // Layout
        if #available(iOS 11.0, *) {
            stackView.setCustomSpacing(10, after: image)
        }

        stackView.activateConstraints {
            $0.matchParentConstraints(top: 25, leading: 25, trailing: -25, bottom: -25)
        }

        return .init(viewable: background) { _ -> ((Utilities.Unit) -> Void) in
            return { _ in }
        }
    }

}
