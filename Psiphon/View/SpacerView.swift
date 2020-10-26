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

@objc final class SpacerView: UIView {
    
    enum Sizing {
        
        /// Flexible implies that SpacerView has no intrinsic size and it is up to the parent view
        /// to size the SpacerView.
        case flexible
        
        /// Sets SpacerView's height to fixed values.
        case fixedHeight(Float)
        
        /// Sets SpacerView's width and height to fixed values.
        case fixed(CGSize)
        
        var cgSize: CGSize {
            switch self {
            case .flexible:
                return CGSize(width: UIView.noIntrinsicMetric,
                              height: UIView.noIntrinsicMetric)
            case .fixedHeight(let height):
                return CGSize(width: UIView.noIntrinsicMetric,
                              height: CGFloat(height))
            case .fixed(let value):
                return value
            }
        }
        
    }
    
    private let sizing: Sizing
    
    init(_ sizing: Sizing) {
        self.sizing = sizing
        super.init(frame: .zero)
        
        self.setContentCompressionResistancePriority(
            (UILayoutPriority(rawValue: 25), .horizontal),
            (UILayoutPriority(rawValue: 25), .vertical)
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        return self.sizing.cgSize
    }
    
}
