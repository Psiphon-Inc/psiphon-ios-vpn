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
import struct PsiApi.SecretString

/// A UITextField that hides it's text in a SecretString type for some
/// additional safety guarantees.
@objc final class SecretValueTextField: UITextField {
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        mutate(self) {
            $0.isSecureTextEntry = true
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var text: String? {
        get {
            return nil
        }
        set {
            super.text = newValue
        }
    }
    
    override var attributedText: NSAttributedString? {
        get {
            return nil
        }
        set {
            super.attributedText = newValue
        }
    }
    
    /// Default value is an empty string.
    var secretText: SecretString {
        SecretString(super.text ?? "")
    }
    
}
