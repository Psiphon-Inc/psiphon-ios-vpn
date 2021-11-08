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

import Foundation
import UIKit
import PsiCashClient

@objc final class PsiCashWidgetView: UIView, Bindable {
    
    typealias BindingType = ViewModel
    
    struct ViewModel: Equatable {
        let balanceViewModel: PsiCashBalanceViewWrapper.BindingType
        let speedBoostButtonModel: SpeedBoostButton.BindingType
        let accountType: PsiCashAccountType?
    }

    @objc let balanceViewWrapper: PsiCashBalanceViewWrapper
    @objc let speedBoostButton: SpeedBoostButton
    @objc let addPsiCashButton = DuskButton()
    @objc let psiCashAccountButton = DuskButton()

    // Horizonal stack containing the top row items.
    private let topRowHStack: UIStackView
    
    override init(frame: CGRect) {
        fatalError()
    }
    
    @objc init(locale: Locale) {
        
        balanceViewWrapper = PsiCashBalanceViewWrapper(locale: locale)
        
        speedBoostButton = SpeedBoostButton(locale: locale)
        
        topRowHStack = UIStackView.make(
            axis: .horizontal,
            distribution: .fill,
            alignment: .center,
            spacing: 10.0
        )
        
        super.init(frame: .zero)
        
        addPsiCashButton.setTitle("+", for: .normal)
        addPsiCashButton.titleLabel!.font = AvenirFont.demiBold.customFont(20.0)
        addPsiCashButton.setTitleColor(.white, for: .normal)
        
        let accountIcon = UIImage(named: "AccountIcon")!
        psiCashAccountButton.setImage(accountIcon, for: .normal)
        
        speedBoostButton.contentEdgeInset(.normal)

        // Adds permanent views to the stack view.
        topRowHStack.addArrangedSubviews(
            balanceViewWrapper.view,
            addPsiCashButton,
            psiCashAccountButton
        )
        
        self.addSubviews(
            topRowHStack,
            speedBoostButton
        )
        
        topRowHStack.activateConstraints {
            $0.constraintToParent(.top(), .centerX()) +
            [
                $0.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor)
            ]
        }

        addPsiCashButton.activateConstraints {
            [
                $0.widthAnchor.constraint(equalToConstant: Style.default.buttonHeight),
                $0.heightAnchor.constraint(equalToConstant: Style.default.buttonHeight)
            ]
        }
        
        psiCashAccountButton.activateConstraints {
            [
                $0.widthAnchor.constraint(equalToConstant: Style.default.buttonHeight),
                $0.heightAnchor.constraint(equalToConstant: Style.default.buttonHeight)
            ]
        }
        
        speedBoostButton.activateConstraints {
            $0.constraintToParent(.bottom(), .leading(), .trailing()) +
                [ $0.topAnchor.constraint(equalTo: topRowHStack.bottomAnchor,
                                          constant: Style.default.padding) ]
        }

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(_ newValue: BindingType) {
        
        balanceViewWrapper.bind(newValue.balanceViewModel)
        speedBoostButton.bind(newValue.speedBoostButtonModel)
        
        switch newValue.accountType {
        case .noTokens, .tracker, .account(loggedIn: false):
            // Shows psiCashAccountButton, if not displayed already.
            if psiCashAccountButton.isHidden {
                topRowHStack.addArrangedSubview(psiCashAccountButton)
                psiCashAccountButton.isHidden = false
            }
            
        case .none, .account(loggedIn: true):
            // PsiCashAccountType is expected to be nil only if PsiCash library fails initialize,
            // or is still being initialized (although Loading screen is expected to be displayed,
            // while the library is initializing.)
            // Hides psiCashAccountButton, if not removed already.
            if !psiCashAccountButton.isHidden {
                topRowHStack.removeArrangedSubview(psiCashAccountButton)
                psiCashAccountButton.isHidden = true
            }

        }
        
    }
    
    @objc func objcBind(_ newValue: BridgedPsiCashWidgetBindingType) {
        self.bind(newValue.swiftValue)
    }
    
}
