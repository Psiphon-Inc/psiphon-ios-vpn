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

/// Represents (eventually all) alerts that are presented modally on top of view controllers.
enum AlertType: String, CaseIterable {
    case psiCashAccountLoginSuccessAlert
}

protocol AlertDismissProtocol {
    func alertDismissed(type: AlertType)
}

extension UINavigationController: AlertDismissProtocol {
    
    func alertDismissed(type: AlertType) {
        for childViewController in self.children {
            if let alertDismissProtocol = childViewController as? AlertDismissProtocol {
                alertDismissProtocol.alertDismissed(type: type)
            }
        }
    }
    
}
