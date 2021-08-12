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

// Adapeted from: https://stackoverflow.com/a/21262188
@objc class FoldingScrollView: UIScrollView, UIScrollViewDelegate {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if (self.layer.mask == nil) {
            let maskLayer = CAGradientLayer()

            maskLayer.locations = [0.0, 0.1, 0.8, 1.0];
            maskLayer.bounds = CGRect(x: 0, y: 0, width: self.frame.size.width, height: self.frame.size.height)
            maskLayer.anchorPoint = CGPoint.zero

            self.layer.mask = maskLayer;
        }
        
        self.scrollViewDidScroll(self)
        
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        
        let transparent = UIColor.white.cgColor
        let opaque = UIColor.clear.cgColor
        
        let colors: [Any]

        if (scrollView.contentOffset.y + scrollView.contentInset.top <= 0) {
            //Top of scrollView
            colors = [transparent, transparent, transparent, opaque]
        } else if (scrollView.contentOffset.y + scrollView.frame.size.height
                   >= scrollView.contentSize.height) {
            //Bottom of scrollView
            colors = [opaque, transparent, transparent, transparent]
        } else {
            //Middle
            colors = [opaque, transparent, transparent, opaque]
        }
        
        (self.layer.mask as? CAGradientLayer)?.colors = colors

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer.mask?.position = CGPoint(x: 0, y: self.contentOffset.y)
        CATransaction.commit()
    }
    
}
