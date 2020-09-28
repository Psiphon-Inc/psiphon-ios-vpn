/*
 * Copyright (c) 2020, Psiphon Inc.
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

final class PsiCashAccountLogInView: UIView {
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let button: GradientButton
    
    init(onLogInTapped: @escaping () -> Void) {
        let title = UILabel.make(text: "Log In to your PsiCash account",
                                 fontSize: .normal,
                                 typeface: .bold,
                                 numberOfLines: 0)
        
        button = GradientButton(gradient: .grey)
        super.init(frame: .zero)
        
        // View properties
        addShadow(toLayer: layer)
        layer.cornerRadius = Style.default.cornerRadius
        backgroundColor = .white(withAlpha: 0.42)
        
        mutate(button) {
            $0.setTitleColor(.darkBlue(), for: .normal)
            $0.setTitle("Log In", for: .normal)
            $0.setTitleColor(.darkBlue(), for: .normal)
            $0.titleLabel?.font = UIFont.avenirNextBold(CGFloat(FontSize.h3.rawValue))
            $0.contentEdgeInsets = Style.default.buttonMinimumContentEdgeInsets
        }
        
        // Adds subviews.
        addSubviews(title, button)
        
        // Sets up AutoLayout.
        title.activateConstraints {
            $0.constraintToParent(.leading(Float(Style.default.padding)), .centerY(0)) + [
                $0.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -20.0)
            ]
        }
        
        button.activateConstraints {
            $0.constraintToParent(.centerY(0), .trailing(-12)) +
                $0.widthConstraint(to: 80, withMax: 150)
        }
        
        button.setEventHandler(onLogInTapped)
    }
    
}
