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

@objc class PsiCashWidgetView: UIView {

    @objc let balanceView = PsiCashBalanceView(frame: CGRect.zero)
    @objc let speedBoostButton = SpeedBoostButton(frame: CGRect.zero)

    override init(frame: CGRect) {
        super.init(frame: frame)

        balanceView.translatesAutoresizingMaskIntoConstraints = false
        speedBoostButton.translatesAutoresizingMaskIntoConstraints = false

        // debug remove
//        speedBoostButton.status = .active(10620)
        speedBoostButton.status = .normal

        addSubview(balanceView)
        addSubview(speedBoostButton)

        NSLayoutConstraint.activate([
            balanceView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            balanceView.topAnchor.constraint(equalTo: self.topAnchor),

            speedBoostButton.heightAnchor.constraint(
                equalTo: speedBoostButton.titleLabel!.heightAnchor, multiplier: 2.3),
            speedBoostButton.topAnchor.constraint(equalTo: balanceView.bottomAnchor, constant: 15),
            speedBoostButton.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            speedBoostButton.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            speedBoostButton.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
