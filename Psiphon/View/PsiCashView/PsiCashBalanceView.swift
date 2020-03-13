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

@objc final class PsiCashBalanceView: UIView, Bindable {
    typealias BindingType = ViewModel
    
    struct ViewModel: Equatable {
        let pendingPsiCashRefresh: PendingPsiCashRefresh
        let balanceState: BalanceState
        
        init(psiCashState: PsiCashState, balanceState: BalanceState) {
            self.pendingPsiCashRefresh = psiCashState.pendingPsiCashRefresh
            self.balanceState = balanceState
        }
    }

    private typealias IconType = EitherView<ImageViewBuidler, EitherView<Spinner, ButtonBuilder>>

    private let title: UILabel
    private let iconContainer = UIView(frame: .zero)
    private let icon: IconType
    private let iconBindable: IconType.BuildType
    private let balance: UILabel
    private let typeface = AvenirFont.bold
    private var state: Loading<PsiCashAmount> = .loaded(PsiCashAmount.zero())

    override init(frame: CGRect) {
        let titleString = UserStrings.PsiCash_balance().localizedUppercase
        let fontSize: FontSize = .h3

        title = UILabel.make(text: titleString,
                             fontSize: fontSize,
                             typeface: typeface,
                             color: UIColor.blueGrey())
        
        balance = UILabel.make(fontSize: fontSize, typeface: typeface)

        guard let coinImage = UIImage(named: "PsiCashCoin") else { fatalError() }
        guard let waitingForExpectedIncreaseImage = UIImage(named: "PsiCash_Alert") else { fatalError() }

        icon = .init(ImageViewBuidler(image: coinImage),
                     .init(Spinner(style: .white),
                           ButtonBuilder(style: .custom, tint: .none, image: waitingForExpectedIncreaseImage, eventHandler: {
                            let alert = UIAlertController(
                                title: UserStrings.PsiCash_balance_out_of_date(),
                                message: UserStrings.Connect_to_psiphon_to_update_psiCash(),
                                preferredStyle: .alert)
                            alert.addAction(.init(title: UserStrings.Done_button_title(),
                                                  style: .default, handler: nil))
                            AppDelegate.getTopMostViewController().present(alert,
                                                                           animated: true,
                                                                           completion: nil)
                           })))
        iconBindable = icon.build(iconContainer)

        super.init(frame: frame)

        layer.masksToBounds = false
        backgroundColor = .clear

        addSubview(title)
        addSubview(iconContainer)
        addSubview(balance)

        title.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        balance.translatesAutoresizingMaskIntoConstraints = false

        iconContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        iconContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iconContainer.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        iconContainer.setContentHuggingPriority(.defaultHigh, for: .vertical)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            title.topAnchor.constraint(equalTo: self.topAnchor),
            title.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            iconContainer.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 3.0),
            iconContainer.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            iconContainer.heightAnchor.constraint(equalToConstant:
                CGFloat(1.33 * fontSize.rawValue)),
            iconContainer.widthAnchor.constraint(equalTo: iconContainer.heightAnchor),

            balance.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 5.0),
            balance.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            balance.topAnchor.constraint(equalTo: self.topAnchor),
            balance.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setAmount(_ amount: PsiCashAmount?) {
        if let amount = amount {
            balance.text = Current.psiCashPriceFormatter.string(from: amount.inPsi)
        } else {
            balance.text = ""
        }
    }

    func bind(_ newValue: BindingType) {
        let iconValue: IconType.BuildType.BindingType
        switch (newValue.pendingPsiCashRefresh,
                newValue.balanceState.pendingExpectedBalanceIncrease) {
        case (.pending, _):
            iconValue = .right(.left(true))  // Spinner
        case (.completed(_), true):
            iconValue = .right(.right(.unit))  // Red "i" info button
        case (.completed(_), false):
            iconValue = .left(.unit)  // Coin icon
        }
        self.setAmount(newValue.balanceState.balance)
        self.iconBindable.bind(iconValue)
    }

}

// ObjC bindings for updating balance view.
extension PsiCashBalanceView {

    @objc func objcBind(_ bindingValue: BridgedBalanceViewBindingType) {
        self.bind(bindingValue.state)
    }

}
