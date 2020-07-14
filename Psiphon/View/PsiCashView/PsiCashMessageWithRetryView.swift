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

struct PsiCashMessageWithRetryView: ViewBuilder {

    enum Message: Equatable {
        case failedToLoadProductList(retryAction: () -> Void)
        case failedToVerifyPsiCashIAPPurchase(retryAction: () -> Void)
        case transactionNotRecordedByAppStore(isRefreshingReceipt: Bool, retryAction: () -> Void)
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.failedToLoadProductList, .failedToLoadProductList):
                return true
            case (.failedToVerifyPsiCashIAPPurchase, .failedToVerifyPsiCashIAPPurchase):
                return true
            case (.transactionNotRecordedByAppStore, .transactionNotRecordedByAppStore):
                return true
            default: return false
            }
        }
    }

    func build(_ container: UIView?) -> StrictBindableViewable<Message, UIView> {
        let root = UIView(frame: .zero)

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit

        let title = UILabel.make(fontSize: .h1,
                                 alignment: .center)

        let subtitle = UILabel.make(fontSize: .h3,
                                    typeface: .medium,
                                    numberOfLines: 0,
                                    alignment: .center)
        
        let retryButton = GradientButton(gradient: .grey)
        retryButton.setTitleColor(.darkBlue(), for: .normal)
        retryButton.titleLabel!.font = AvenirFont.demiBold.font(.normal)
        retryButton.contentEdgeInsets = Style.default.buttonContentEdgeInsets
        
        let spinner = UIActivityIndicatorView(style: .whiteLarge)
        spinner.isHidden = true

        // Add subviews
        root.addSubviews(imageView, title, subtitle, retryButton, spinner)

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

        retryButton.activateConstraints {
            $0.constraintToParent(.centerX(0)) +
                [ $0.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20) ]
        }
        
        spinner.activateConstraints {
            $0.constraintToParent(.centerX(0)) +
                [ $0.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20) ]
        }

        return .init(viewable: root) { [imageView, title, subtitle] _ -> ((Message) -> Void) in
            return { [imageView, title, subtitle] msg in
                switch msg {
                case .failedToLoadProductList(let retryAction):
                    imageView.image = UIImage(named: "PsiCashCoinCloud")!
                    title.text = UserStrings.Failed_to_load()
                    subtitle.text = UserStrings.Product_list_could_not_be_retrieved()
                    retryButton.setEventHandler(retryAction)
                    retryButton.setTitle(UserStrings.Tap_to_retry(), for: .normal)
                    
                case .failedToVerifyPsiCashIAPPurchase(let retryAction):
                    imageView.image = UIImage(named: "PsiCashPendingTransaction")!
                    title.text = UserStrings.Failed_to_verify_psicash_purchase()
                    subtitle.text = UserStrings.Please_try_again_later()
                    retryButton.setEventHandler(retryAction)
                    retryButton.setTitle(UserStrings.Tap_to_retry(), for: .normal)
                    
                case let .transactionNotRecordedByAppStore(isRefreshingReceipt: isRefreshingReceipt,
                                                           retryAction: retryAction):
                    imageView.image = UIImage(named: "PsiCashPendingTransaction")!
                    title.text = UserStrings.Purchase_not_recorded_by_AppStore()
                    subtitle.text = UserStrings.Refresh_app_receipt_to_try_again()
                    retryButton.setEventHandler(retryAction)
                    retryButton.setTitle(UserStrings.Refresh_receipt_button_title(),
                                         for: .normal)
                    
                    // Shows spinner while the receipt is being refreshed.
                    if isRefreshingReceipt {
                        spinner.isHidden = false
                        spinner.startAnimating()
                        retryButton.isHidden = true
                        retryButton.isUserInteractionEnabled = false
                    } else {
                        spinner.isHidden = true
                        spinner.stopAnimating()
                        retryButton.isHidden = false
                        retryButton.isUserInteractionEnabled = true
                    }
                    
                }
            }
        }
    }

}
