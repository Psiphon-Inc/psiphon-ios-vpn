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

@objc class PsiCashBalanceView: UIView {

    // Subviews
    let title: UILabel
    let psiCashIcon: UIImageView
    let balance: UILabel

    let typeface = AvenirFont.bold

    // Attributes
    let numberFormatter = NumberFormatter()
    let fontSize: CGFloat = 14.0

    override init(frame: CGRect) {
        // TODO! replace this with localized version:
        let titleString = "PsiCash Balance:".localizedUppercase

        title = makeLabel(text: titleString,
                          fontSize: fontSize,
                          typeface: typeface,
                          color: UIColor.blueGrey())

        balance = makeLabel(fontSize: fontSize, typeface: typeface)

        psiCashIcon = UIImageView(image: UIImage(named: "PsiCashCoin"))
        psiCashIcon.contentMode = .scaleAspectFit

        numberFormatter.numberStyle = .decimal

        super.init(frame: frame)
        layer.masksToBounds = false
        backgroundColor = .clear

        addSubview(title)
        addSubview(psiCashIcon)
        addSubview(balance)

        setChildrenAutoresizingMaskIntoConstraintsFlagToFalse(forView: self)

        psiCashIcon.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        psiCashIcon.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            title.topAnchor.constraint(equalTo: self.topAnchor),
            title.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            psiCashIcon.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 3.0),
            psiCashIcon.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            psiCashIcon.heightAnchor.constraint(equalTo: self.heightAnchor),

            balance.leadingAnchor.constraint(equalTo: psiCashIcon.trailingAnchor, constant: 5.0),
            balance.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            balance.topAnchor.constraint(equalTo: self.topAnchor),
            balance.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAmount(_ amount: PsiCashAmount) {
        balance.text = numberFormatter.string(from: NSNumber(value: amount.inPsi))
    }

    @objc func setAmount(nanoPsi: Int64) {
        setAmount(PsiCashAmount(nanoPsi: nanoPsi))
    }

}
