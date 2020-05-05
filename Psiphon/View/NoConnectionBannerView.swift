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

@objc final class NoConnectionBannerView: UIView {
    
    private let title: UILabel
    
    init() {
        self.title = UILabel.make(
            text: UserStrings.No_internet_connection(),
            fontSize: .normal,
            typeface: .medium,
            color: .white,
            numberOfLines: 1,
            alignment: .center
        )
        
        super.init(frame: .zero)
        
        self.backgroundColor = UIColor.black
        self.addSubview(title)
        
        self.title.activateConstraints {
            $0.constraintToParent(.centerX(0), .bottom(-10))
        }
        
    }

    required init?(coder: NSCoder) {
        fatalErrorFeedbackLog("init(coder:) has not been implemented")
    }

}
