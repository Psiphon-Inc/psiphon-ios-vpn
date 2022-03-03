/*
 * Copyright (c) 2022, Psiphon Inc.
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

import Foundation
import UIKit

/// A child view controller is a view controller that is presented by container view controller (e.g. UINavigationController).
/// It is not presented modally.
public protocol ChildViewControllerDismissedDelegate {
    
    /// Tells the delegate the the parent view controller is dismissed.
    func parentIsDimissed()
    
}

/// Modified `UINavigationController` with default app styling.
open class NavigationController: UINavigationController {
    
    public override init(rootViewController: UIViewController) {
        
        guard let _ = rootViewController as? ChildViewControllerDismissedDelegate else {
            fatalError("rootViewController should conform to ChildViewControllerDismissedDelegate")
        }
        
        super.init(rootViewController: rootViewController)
        
    }
    
    override public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func addChild(_ childController: UIViewController) {
        
        guard let _ = childController as? ChildViewControllerDismissedDelegate else {
            fatalError("childController should conform to ChildViewControllerDismissedDelegate")
        }
        
        super.addChild(childController)
        
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        
        // A UINavigationController is only presented modally.
        if self.isBeingDismissed {
            for childVC in self.children {
                guard let childVC = childVC as? ChildViewControllerDismissedDelegate else {
                    fatalError()
                }
                childVC.parentIsDimissed()
            }
        }
        
    }
    
    
}

#endif
