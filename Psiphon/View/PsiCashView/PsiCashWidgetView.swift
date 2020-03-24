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
    private let topRowLayoutGuide = UILayoutGuide()

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addPsiCashButton.setTitle("+", for: .normal)
        addPsiCashButton.titleLabel!.font = AvenirFont.demiBold.customFont(20.0)
        addPsiCashButton.setTitleColor(.white, for: .normal)
        addPsiCashButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        
        speedBoostButton.contentEdgeInset(.normal)

        addLayoutGuide(topRowLayoutGuide)
        addSubview(speedBoostButton)
        addSubview(balanceView)
        addSubview(addPsiCashButton)
        
        topRowLayoutGuide.activateConstraints {
            [ $0.topAnchor.constraint(equalTo: self.topAnchor),
              $0.bottomAnchor.constraint(equalTo: balanceView.bottomAnchor),
              $0.leadingAnchor.constraint(equalTo: balanceView.leadingAnchor),
              $0.trailingAnchor.constraint(equalTo: addPsiCashButton.trailingAnchor),
              $0.centerXAnchor.constraint(equalTo: self.centerXAnchor) ]
        }
        
        balanceView.activateConstraints {
            $0.constraint(to: topRowLayoutGuide, [.leading(0), .top(0)]) +
                [ $0.centerYAnchor.constraint(equalTo: addPsiCashButton.centerYAnchor) ]
        }
        
        addPsiCashButton.activateConstraints {
            [ $0.topAnchor.constraint(equalTo: balanceView.topAnchor),
              $0.leadingAnchor.constraint(equalTo: balanceView.trailingAnchor, constant: 10.0) ]
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
