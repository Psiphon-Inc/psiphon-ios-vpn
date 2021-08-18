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
    private typealias IconType = EitherView<ImageViewBuilder, Spinner>

    private let locale: Locale
    private let psiCashAmountFormatter: PsiCashAmountFormatter
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
        fatalError()
    }

    init(locale: Locale) {
        
        let titleString = UserStrings.PsiCash_balance().uppercased(with: locale)
        let fontSize: FontSize = .normal
        
        self.locale = locale
        
        psiCashAmountFormatter = PsiCashAmountFormatter(locale: locale)
        
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
        
        balanceView = EFCountingLabel(frame: .zero)
        balanceView.apply(fontSize: fontSize, typeface: typeface)

        guard let coinImage = UIImage(named: "PsiCashCoin") else {
            fatalError("Could not find 'PsiCashCoin' image")
        }
        
        icon = EitherView(
            ImageViewBuilder(image: coinImage),
            Spinner(style: .white)
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
            label.text = self.psiCashAmountFormatter.string(from: Double(value).rounded(.down))
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
        
        switch newValue.balanceState.pendingPsiCashRefresh {
        case .pending:
            iconValue = .right(true) // Spinner icon
        case .completed(_):
            iconValue = .left(.unit) // PsiCash coin icon
        }
        
        let balance = newValue.balanceState.psiCashBalance.optimisticBalance
        self.setAmount(balance)
        
        
        // 4" iPhone SE          320x568 pt
        // 4.7" iPhone SE        375x667 pt
        // iPhone 6              375x667 pt
        // iPhone 11 Pro Max     414x896 pt
        // iPhone 12 Pro Max     428x926 pt
        let deviceWidth = UIScreen.main.bounds.width
        
        // "PsiCash Balance" label does not fit on smaller for large balances,
        // so we will hide it.
        if deviceWidth < 375 {
            // Empty title
            self.title.text = ""
            
        } else if deviceWidth <= 428 {
            
            if balance < PsiCashAmount(nanoPsi: 10_000_000_000_000) /* 10,000 PsiCash */ {
                // "PsiCash Balance" title
                self.title.text = UserStrings.PsiCash_balance().uppercased(with: locale)
            } else {
                // Empty title
                self.title.text = ""
            }
            
        } else {
            // "PsiCash Balance" title
            self.title.text = UserStrings.PsiCash_balance().uppercased(with: locale)
        }
        
        self.iconBindable.bind(iconValue)
    }

}
