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

#if os(iOS)
import UIKit

public extension UIViewController {

    /// This method is an attempt to organize dismissal of view controller's in order
    /// to build a typed navigation hierarchy.
    /// This method is functionally equivalent to calling dismiss on the presented view controller.
    static func safeDismiss(
        _ viewControllerToDismiss: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)?
    ) {
        viewControllerToDismiss.dismiss(animated: flag, completion: completion)
    }
    
    /// `true` if this view controller is the root of the parent navigation controller, `false` otherwise.
    var isRootViewController: Bool {
        if let navigationController = self.navigationController {
            return navigationController.children[0] === self
        } else {
            return false
        }
    }

}

#endif
