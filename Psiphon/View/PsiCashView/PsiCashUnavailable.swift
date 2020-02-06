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

/// ViewBuilder for the "PsiCash Unavailable" screen.
struct PsiCashUnavailable: ViewBuilder {

    enum Message {
        case unavailableWhileConnecting
        case otherErrorTryAgain
    }

    func build(_ container: UIView?) -> MutableBindableViewable<Message, UIView> {
        let root = UIView(frame: .zero)

        let image = UIImageView.make(image: "PsiCashCoinCloud")

        let title = UILabel.make(text: UserStrings.PsiCash_unavailable(),
            fontSize: .h1,
            alignment: .center)

        let subtitle = UILabel.make(text: UserStrings.Please_try_again_later(),
            fontSize: .h3,
            typeface: .medium,
            numberOfLines: 0,
            alignment: .center)

        // Add subviews
        root.addSubviews(image, title, subtitle)
        container!.addSubview(root)

        // Autolayout
        root.activateConstraints {
            $0.constraintToParent(.leading(), .trailing(),.centerX(), .centerY())
        }

        image.activateConstraints {
            $0.constraintToParent(.top(), .centerX())
        }

        title.activateConstraints {
            $0.constraintToParent(.leading(), .trailing()) +
                [ $0.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 20) ]
        }

        subtitle.activateConstraints {
            $0.constraintToParent(.leading(), .trailing(), .bottom()) +
                [ $0.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 13) ]
        }

        return .init(viewable: root) { _ -> ((PsiCashUnavailable.Message) -> UIView?) in
            return { msg in
                switch msg {
                case .unavailableWhileConnecting:
                    subtitle.text = UserStrings.PsiCash_is_unavailable_while_connecting_to_psiphon()
                case .otherErrorTryAgain:
                    subtitle.text = UserStrings.Please_try_again_later()
                }
                return nil
            }
        }
    }

}
