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

import Foundation
import UIKit
import PsiApi

/// Modified `NavigationController` with default app styling.
@objc final class PsiNavigationController: NavigationController {
    
    private let applyPsiphonStyling: Bool
    
    // Patch for Swift bug on iOS 12.
    // @unavailable(iOS 13, *)
    override init(nibName: String?, bundle: Bundle?) {
        self.applyPsiphonStyling = true
        super.init(nibName: nibName, bundle: bundle)
    }
    
    @objc init(rootViewController: UIViewController, applyPsiphonStyling: Bool = true) {
        self.applyPsiphonStyling = applyPsiphonStyling
        super.init(rootViewController: rootViewController)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // Fixes navigation bar appearance when scrolling.
        self.navigationBar.applyStandardAppearanceToScrollEdge()

        if self.applyPsiphonStyling {
            self.navigationBar.tintColor = .white
            self.navigationBar.applyPsiphonNavigationBarStyling()
        }
        
    }
    
}
