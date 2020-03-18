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

struct PsiCashMessageView: ViewBuilder {

    enum Message {
        case pendingPsiCashVerification
        case speedBoostAlreadyActive
        case userSubscribed
        case unavailableWhileConnecting
        case otherErrorTryAgain
    }

    func build(_ container: UIView?) -> MutableBindableViewable<Message, UIView> {
        let root = UIView(frame: .zero)

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit

        let title = UILabel.make(fontSize: .h1,
                                 alignment: .center)

        let subtitle = UILabel.make(fontSize: .h3,
                                    typeface: .medium,
                                    numberOfLines: 0,
                                    alignment: .center)

        // Add subviews
        root.addSubviews(imageView, title, subtitle)
        container!.addSubview(root)

        // Autolayout
        root.activateConstraints {
            $0.constraintToParent(.leading(), .trailing(),.centerX(), .centerY())
        }

        imageView.activateConstraints {
            $0.constraintToParent(.top(), .centerX())
        }

        title.activateConstraints {
            $0.constraintToParent(.leading(), .trailing()) +
                [ $0.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20) ]
        }

        subtitle.activateConstraints {
            $0.constraintToParent(.leading(), .trailing(), .bottom()) +
                [ $0.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 13) ]
        }

        return .init(viewable: root) { [imageView, title, subtitle] _ -> ((PsiCashMessageView.Message) -> UIView?) in
            return { [imageView, title, subtitle] msg in
                switch msg {
                case .pendingPsiCashVerification:
                    imageView.image = UIImage(named: "PsiCashPendingTransaction")
                    title.text = UserStrings.PsiCash_transaction_pending()
                    subtitle.text = UserStrings.PsiCash_wait_for_transaction_to_be_verified()

                case .speedBoostAlreadyActive:
                    imageView.image = UIImage(named: "SpeedBoostActive")!
                    title.text = UserStrings.Speed_boost_active()
                    subtitle.text = UserStrings.Speed_boost_you_already_have()

                case .userSubscribed:
                    imageView.image =  UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.PsiCash_unavailable()
                    subtitle.text = UserStrings.PsiCash_is_unavailable_while_subscribed()

                case .unavailableWhileConnecting:
                    imageView.image =  UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.PsiCash_unavailable()
                    subtitle.text = UserStrings.PsiCash_is_unavailable_while_connecting_to_psiphon()
                    
                case .otherErrorTryAgain:
                    imageView.image =  UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.PsiCash_unavailable()
                    subtitle.text = UserStrings.Please_try_again_later()
                }
                return nil
            }
        }
    }

}

