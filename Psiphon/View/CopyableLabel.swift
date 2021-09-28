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

final class CopyableLabel: UILabel {

    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 13.0, *) {
            isUserInteractionEnabled = true
            addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                              action: #selector(showMenu)))
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    @objc func showMenu(sender: AnyObject?) {
        if #available(iOS 13.0, *) {
            self.becomeFirstResponder()
            
            let menu = UIMenuController.shared
            
            if !menu.isMenuVisible {
                menu.showMenu(from: self, rect: bounds)
            }
        }
    }
    
    @objc override func copy(_ sender: Any?) {
        if #available(iOS 13.0, *) {
            UIPasteboard.general.string = text
            UIMenuController.shared.showMenu(from: self, rect: bounds)
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == #selector(UIResponderStandardEditActions.copy)
    }
    
}
