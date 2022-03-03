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
import PsiApi

/// Modified `NavigationController` with default app styling.
@objc public final class PsiNavigationController: NavigationController {
    
    public override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.navigationBar.tintColor = .white
        
        // Fixes navigation bar appearance when scrolling.
        self.navigationBar.applyStandardAppearanceToScrollEdge()

        self.navigationBar.applyPsiphonNavigationBarStyling()
        
    }
    
}
