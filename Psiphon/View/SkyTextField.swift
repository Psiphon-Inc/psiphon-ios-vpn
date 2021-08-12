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
import UIKit

/// Sky themed UITextField.
final class SkyTextField<TextField: UITextField>: UIView {
    
    let textField: TextField
    
    var hasText: Bool {
        textField.hasText
    }
    
    init(placeHolder: String, textColor: UIColor = .white, margin: Float = 5.0) {
        
        self.textField = TextField.init(frame: .zero)
        super.init(frame: .zero)
        
        mutate(self) {
            $0.addSubview(textField)
            $0.backgroundColor = .white(withAlpha: 0.15)
            $0.layer.cornerRadius = Style.default.cornerRadius
        }
        
        mutate(textField) {
            $0.font = .avenirNextMedium(CGFloat(FontSize.h2.rawValue))
            $0.textColor = textColor
            
            $0.attributedPlaceholder = NSAttributedString(
                string: placeHolder,
                attributes: [NSAttributedString.Key.foregroundColor:
                                textColor.withAlphaComponent(0.25)]
            )
        }
        
        textField.activateConstraints {
            $0.matchParentConstraints(top: margin, leading: margin,
                                      trailing: -margin, bottom: -margin)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
