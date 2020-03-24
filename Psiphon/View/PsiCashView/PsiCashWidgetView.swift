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

@objc final class PsiCashWidgetView: UIView {

    @objc let balanceView = PsiCashBalanceView(frame: CGRect.zero)
    @objc let speedBoostButton = SpeedBoostButton()
    @objc let addPsiCashButton = DuskButton()
    @objc let topRowStackView = UIStackView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addPsiCashButton.setTitle("+", for: .normal)
        addPsiCashButton.titleLabel!.font = AvenirFont.demiBold.customFont(20.0)
        addPsiCashButton.setTitleColor(.white, for: .normal)
        addPsiCashButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        
        speedBoostButton.contentEdgeInset(.normal)
        
        topRowStackView.axis = .horizontal
        topRowStackView.distribution = .fillProportionally
        topRowStackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        topRowStackView.spacing = 8.0

        addSubview(topRowStackView)
        addSubview(speedBoostButton)
        topRowStackView.addArrangedSubview(balanceView)
        topRowStackView.addArrangedSubview(addPsiCashButton)

        topRowStackView.activateConstraints {
            $0.constraintToParent(.centerX(0), .top(0))
        }

        speedBoostButton.activateConstraints {
            $0.constraintToParent(.bottom(), .leading(), .trailing()) +
                [ $0.topAnchor.constraint(equalTo: balanceView.bottomAnchor,
                                          constant: Style.default.padding) ]
        }

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
