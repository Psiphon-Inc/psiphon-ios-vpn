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
        case unavailableWhileDisconnecting
        case otherErrorTryAgain
        case signupOrLoginToPsiCash
        case psiCashAccountsLoggingIn
        case psiCashAccountsLoggingOut
    }

    func build(_ container: UIView?) -> ImmutableBindableViewable<Message, UIView> {
        
        // vStack is contained in wrapper, letting the wrapper
        // grow beyond the vStack natural size..
        let wrapper = UIView(frame: .zero)
        
        let vStack = UIStackView.make(
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
                                    numberOfLines: 0)

        // Add subviews
        vStack.addArrangedSubviews(
            imageView,
            title,
            subtitle
        )
        
        wrapper.addSubviews(vStack)
        
        vStack.activateConstraints {
            $0.constraintToParent(.centerX(), .top(Float(Style.default.largePadding)),
                                  .leading(), .trailing())
        }
        
        wrapper.activateConstraints {
            [
                $0.bottomAnchor.constraint(greaterThanOrEqualTo: vStack.bottomAnchor)
            ]
        }

        return .init(viewable: wrapper) { [imageView, title, subtitle] _ -> ((PsiCashMessageView.Message) -> Void) in
            return { [imageView, title, subtitle] msg in
                switch msg {
                case .pendingPsiCashVerification:
                    imageView.image = UIImage(named: "PsiCashPendingTransaction")
                    title.text = UserStrings.PsiCash_transaction_pending()
                    subtitle.text = UserStrings.PsiCash_wait_for_transaction_to_be_verified()
                    subtitle.textAlignment = .center

                case .speedBoostAlreadyActive:
                    imageView.image = UIImage(named: "SpeedBoostActive")!
                    title.text = UserStrings.Speed_boost_active()
                    subtitle.text = UserStrings.Speed_boost_you_already_have()
                    subtitle.textAlignment = .center

                case .userSubscribed:
                    imageView.image =  UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.PsiCash_subscription_already_gives_premium_access_title()
                    subtitle.text = UserStrings.PsiCash_subscription_already_gives_premium_access_body()
                    subtitle.textAlignment = .natural

                case .unavailableWhileConnecting:
                    imageView.image =  UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.PsiCash_unavailable()
                    subtitle.text = UserStrings.PsiCash_is_unavailable_while_connecting_to_psiphon()
                    subtitle.textAlignment = .center
                    
                case .unavailableWhileDisconnecting:
                    imageView.image =  UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.PsiCash_unavailable()
                    subtitle.text = UserStrings.PsiCash_is_unavailable_while_disconnecting_from_psiphon()
                    subtitle.textAlignment = .center
                    
                case .otherErrorTryAgain:
                    imageView.image =  UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.PsiCash_unavailable()
                    subtitle.text = UserStrings.Please_try_again_later()
                    subtitle.textAlignment = .center
                
                case .signupOrLoginToPsiCash:
                    imageView.image = UIImage(named: "PsiCashCoinCloud")!
                    title.text = ""
                    subtitle.text = UserStrings.Sign_up_or_login_to_psicash_account_to_continue()
                    subtitle.textAlignment = .center
                    
                case .psiCashAccountsLoggingIn:
                    imageView.image = UIImage(named: "RedRocket")!
                    title.text = UserStrings.Logging_in_ellipses()
                    subtitle.text = ""
                
                case .psiCashAccountsLoggingOut:
                    imageView.image = UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.Logging_out_ellipses()
                    subtitle.text = ""
                    
                }
            }
        }
    }

}

