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
    @objc let speedBoostButton = SpeedBoostButton()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(balanceView)
        addSubview(speedBoostButton)

        speedBoostButton.contentEdgeInset(.normal)

        balanceView.activateConstraints {
            $0.constraintToParent(.centerX(), .top())
        }

        speedBoostButton.activateConstraints {
            $0.constraintToParent(.bottom(), .leading(), .trailing()) +
                [ $0.topAnchor.constraint(equalTo: balanceView.bottomAnchor, constant: Style.default.padding) ]
        }

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
