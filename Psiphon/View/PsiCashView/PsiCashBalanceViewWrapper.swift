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
import EFCountingLabel
import PsiCashClient

struct PsiCashBalanceViewModel: Equatable {
    /// `true` if PsiCash state has been restored from the PsiCash library.
    let psiCashLibLoaded: Bool
    let balanceState: BalanceState
}

@objc final class PsiCashBalanceViewWrapper: NSObject, ViewWrapper, Bindable {
    typealias BindingType = PsiCashBalanceViewModel
    private typealias IconType = EitherView<ImageViewBuilder, EitherView<Spinner, ButtonBuilder>>

    private let psiCashPriceFormatter = PsiCashAmountFormatter(locale: Locale.current)
    private let vStack: UIStackView
    private let hStack: UIStackView
    private let title: UILabel
    private let iconContainer = UIView(frame: .zero)
    private let icon: IconType
    private let iconBindable: IconType.BuildType
    private let balanceView: EFCountingLabel
    private let typeface = AvenirFont.bold
    
    private var currentAmount: PsiCashAmount?
    
    @objc var view: UIView {
        vStack
    }

    override init() {
        
        let titleString = UserStrings.PsiCash_balance().localizedUppercase
        let fontSize: FontSize = .normal
        
        vStack = UIStackView.make(
            axis: .vertical,
            distribution: .fill,
            alignment: .center
        )
        
        hStack = UIStackView.make(
            axis: .horizontal,
            distribution: .fill,
            alignment: .center,
            spacing: 2.0
        )

        title = UILabel.make(text: titleString,
                             fontSize: fontSize,
                             typeface: typeface,
                             color: UIColor.blueGrey())
        
        balanceView = UILabel.make(fontSize: fontSize, typeface: typeface)

        guard let coinImage = UIImage(named: "PsiCashCoin") else {
            fatalError("Could not find 'PsiCashCoin' image")
        }
        guard let waitingForExpectedIncreaseImage = UIImage(named: "PsiCash_Alert") else {
            fatalError("Could not find 'PsiCash_Alert' image")
        }

        icon = EitherView(
            ImageViewBuilder(image: coinImage),
            EitherView(
                Spinner(style: .white),
                ButtonBuilder(style: .custom, tint: .none, image: waitingForExpectedIncreaseImage) {
                    let alert = UIAlertController(
                        title: UserStrings.PsiCash_balance_out_of_date(),
                        message: UserStrings.Connect_to_psiphon_to_update_psiCash(),
                        preferredStyle: .alert)
                    alert.addAction(.init(title: UserStrings.Done_button_title(),
                                          style: .default, handler: nil))
                    AppDelegate.getTopPresentedViewController().present(alert,
                                                                        animated: true,
                                                                        completion: nil)
                })
        )
        
        iconBindable = icon.build(iconContainer)

        super.init()
        
        // Sets some default value so that hStack's
        // width and horizontal position are not ambiguous.
        iconBindable.bind(.left(.unit))
        
        vStack.addArrangedSubview(hStack)
        
        hStack.addArrangedSubviews(
            title,
            iconContainer,
            balanceView
        )
        
        iconContainer.activateConstraints {[
            $0.heightAnchor.constraint(equalToConstant: CGFloat(1.33 * fontSize.rawValue))
                .priority(.belowRequired),
            $0.widthAnchor.constraint(equalTo: $0.heightAnchor)
        ]}
        
        // Additional constraints so that hStack height would not grow
        // beyond the tallest view (in this case the title view).
        self.hStack.activateConstraints {
            $0.constraint(to: title, .top(), .bottom())
        }
        
        balanceView.setUpdateBlock { [unowned self] (value, label) in
            label.text = self.psiCashPriceFormatter.string(from: Double(value).rounded(.down))
        }
        
        balanceView.counter.timingFunction = EFTimingFunction.easeInOut(easingRate: 5)
    }

    private func setAmount(_ newAmount: PsiCashAmount?) {
        guard newAmount != currentAmount else {
            return
        }
        defer {
            currentAmount = newAmount
        }
        if let newAmount = newAmount {
            let newAmountF = CGFloat(newAmount.inPsi)
            
            if let current = currentAmount {
                let currentAmountF = CGFloat(current.inPsi)
                balanceView.countFrom(currentAmountF, to: newAmountF, withDuration: 1.0)
                
            } else {
                // Don't animate the first time value is set
                balanceView.countFrom(newAmountF, to: newAmountF, withDuration: 0.0)
            }
                        
        } else {
            balanceView.text = "-"
        }
    }

    func bind(_ newValue: BindingType) {
        guard newValue.psiCashLibLoaded else {
            return
        }
        let iconValue: IconType.BuildType.BindingType
        switch (newValue.balanceState.pendingPsiCashRefresh,
                newValue.balanceState.psiCashBalance.balanceOutOfDateReason) {
        case (.pending, _):
            iconValue = .right(.left(true))  // Spinner
        
        case (.completed(_), .purchasedPsiCash):
            iconValue = .right(.right(.unit))  // Red "i" info button
        
        case (.completed(_), .none),
             (.completed(_), .watchedRewardedVideo):
            iconValue = .left(.unit)  // Coin icon
        
        case (_, .otherBalanceUpdateError),
             (_, .psiCashDataStoreMigration):
            iconValue = .right(.right(.unit))  // Red "i" info button
        }
        
        self.setAmount(newValue.balanceState.psiCashBalance.optimisticBalance)
        self.iconBindable.bind(iconValue)
    }

}
