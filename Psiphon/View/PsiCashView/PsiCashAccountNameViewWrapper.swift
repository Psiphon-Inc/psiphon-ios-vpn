/*
 * Copyright (c) 2021, Psiphon Inc.
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


final class PsiCashAccountNameViewWrapper: NSObject, ViewWrapper, Bindable {
    
    private let hStack: UIStackView
    
    private let label: CopyableLabel
    
    @objc var view: UIView {
        hStack
    }

    override init() {
        
        hStack = UIStackView.make(
            axis: .horizontal,
            distribution: .equalSpacing,
            alignment: .center,
            spacing: 5.0
        )
        
        label = CopyableLabel.make(
            fontSize: .normal,
            typeface: .demiBold,
            color: .white
        )

        super.init()
        
        let accountIcon = UIImage(named: "AccountIcon")!
        let accountIconView = UIImageView(image: accountIcon)
        
        hStack.addArrangedSubviews(
            accountIconView,
            label
        )
        
        // Limits height of the hStack to the label.
        self.hStack.activateConstraints {
            [ $0.heightAnchor.constraint(equalTo: label.heightAnchor) ]
        }
        
    }

    func bind(_ newValue: String) {
        guard !newValue.isEmpty else {
            fatalError("account name cannot be empty")
        }
        label.text = newValue
    }

}
