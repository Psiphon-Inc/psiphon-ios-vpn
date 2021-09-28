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

struct PsiCashMessageViewWithButton: ViewBuilder {

    enum Message: Equatable {
        
        enum UntunneledMessage: Equatable {
            
            enum SpeedBoostUnavailableMessage: Equatable {
                case tryAgainLater
                case connectToPsiphon
            }
            
            case speedBoostAlreadyActive
            case speedBoostUnavailable(subtitle: SpeedBoostUnavailableMessage)
            case pendingPsiCashPurchase
        }
        
        case untunneled(UntunneledMessage)
        
    }

    let action: (Message) -> Void

    func build(_ container: UIView?) -> ImmutableBindableViewable<Message, UIView> {
        
        let stackView = UIStackView.make(
            axis: .vertical,
            distribution: .fill,
            alignment: .fill,
            spacing: Style.default.padding,
            margins: (top: 5.0, bottom: Style.default.padding)
        )

        let imageView = UIImageView.make(
            contentMode: .scaleAspectFit,
            easyToShrink: true
        )

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

        // Add subviews
        stackView.addArrangedSubviews(
            imageView,
            title,
            subtitle,
            SpacerView(.flexible),
            button
        )
        
        button.activateConstraints {[
            $0.heightAnchor.constraint(equalToConstant: Style.default.largeButtonHeight)
        ]}

        return .init(viewable: stackView) { _ -> ((Message) -> Void) in
            return { message in
                
                switch message {
                    
                case .untunneled(let untunneledMessage):
                    
                    switch untunneledMessage {
                        
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
                    
                    button.setTitle(UserStrings.Connect_to_psiphon_button(), for: .normal)
                    
                }
                
                // Updates button event handler.
                button.setEventHandler {
                    self.action(message)
                }

            }
        }
    }

}
