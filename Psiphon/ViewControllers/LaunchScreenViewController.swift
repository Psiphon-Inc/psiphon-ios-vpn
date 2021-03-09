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

@objc final class LaunchScreenViewController: UIViewController {
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .darkBlue()
        
        let launchScreenView = Bundle.main.loadNibNamed("LaunchScreen", owner: self, options: nil)![0] as! UIView
        
        // Loading label
        let loadingLabel = UILabel.make(text: UserStrings.Loading(),
                                        fontSize: .h2,
                                        typeface: .medium,
                                        color: .white,
                                        alignment: .center)
        
        
        // Adds views to parent
        self.view.addSubviews(launchScreenView, loadingLabel)
        
        
        // Autolayout
        
        let rootViewLayoutGuide = makeSafeAreaLayoutGuide(addToView: self.view)
        
        launchScreenView.activateConstraints {
            $0.matchParentConstraints()
        }
        
        loadingLabel.activateConstraints {
            $0.constraint(to: rootViewLayoutGuide, .centerX(0), .bottom(-50))
        }
        
        self.setNeedsStatusBarAppearanceUpdate()
        
    }
    
}
