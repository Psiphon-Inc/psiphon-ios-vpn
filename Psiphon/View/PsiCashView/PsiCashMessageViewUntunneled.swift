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

struct PsiCashMessageViewUntunneled: ViewBuilder {

    enum Message: Equatable {
        case speedBoostAlreadyActive
        case speedBoostUnavailable(subtitle: SpeedBoostUnavailableMessage)
        case pendingPsiCashPurchase
    }

    enum SpeedBoostUnavailableMessage: Equatable {
        case tryAgainLater
        case connectToPsiphon
    }

    let action: () -> Void

    func build(_ container: UIView?) -> StrictBindableViewable<Message, UIView> {
        let root = UIView(frame: .zero)

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit

        let title = UILabel.make(fontSize: .h1,
                                 numberOfLines: 0,
                                 alignment: .center)

        let subtitle = UILabel.make(fontSize: .h3,
                                    typeface: .medium,
                                    numberOfLines: 0,
                                    alignment: .center)

        let button = GradientButton(gradient: .grey)
        button.setTitleColor(.darkBlue(), for: .normal)
        button.titleLabel!.font = AvenirFont.demiBold.font(.h3)
        button.setTitle(UserStrings.Connect_to_psiphon_button(), for: .normal)
        button.setEventHandler(self.action)

        // Add subviews
        root.addSubviews(imageView, title, subtitle, button)

        // Autolayout
        imageView.activateConstraints {
            $0.constraintToParent(.top(40), .centerX())
        }

        title.activateConstraints {
            $0.constraintToParent(.leading(), .trailing()) +
                [ $0.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20) ]
        }

        subtitle.activateConstraints {
            $0.constraintToParent(.leading(), .trailing()) +
                [ $0.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 13) ]
        }

        button.activateConstraints {
            $0.constraintToParent(.leading(), .trailing(), .bottom(Float(-Style.default.padding))) +
                [ $0.heightAnchor.constraint(equalToConstant: Style.default.largeButtonHeight) ]
        }

        return .init(viewable: root) { _ -> ((Message) -> Void) in
            return { message in
                switch message {
                case .speedBoostAlreadyActive:
                    imageView.image = UIImage(named: "SpeedBoostActive")!
                    title.text = UserStrings.Speed_boost_active()
                    subtitle.text = UserStrings.Speed_boost_you_already_have()

                case let .speedBoostUnavailable(subtitle: subtitleMessage):
                    imageView.image = UIImage(named: "SpeedBoostUnavailable")
                    title.text = UserStrings.Speed_boost_unavailable()
                    switch subtitleMessage {
                    case .connectToPsiphon:
                        subtitle.text = UserStrings.Connect_to_psiphon_to_use_speed_boost()
                    case .tryAgainLater:
                        subtitle.text = UserStrings.Please_try_again_later()
                    }

                case .pendingPsiCashPurchase:
                    imageView.image = UIImage(named: "PsiCashPendingTransaction")
                    title.text = UserStrings.PsiCash_transaction_pending()
                    subtitle.text = UserStrings.Connect_to_finish_psicash_transaction()
                }

            }
        }
    }

}
