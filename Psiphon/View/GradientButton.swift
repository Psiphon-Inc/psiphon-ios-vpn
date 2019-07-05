/*
* Copyright (c) 2019, Psiphon Inc.
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

@objc class GradientButton: AnimatedUIButton {

    let gradient = CAGradientLayer()

    var gradientColors: [CGColor] {
        didSet {
            gradient.colors = gradientColors
            //setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        gradientColors = defaultGradientColors

        super.init(frame: frame)

        backgroundColor = UIColor.clear
        layer.cornerRadius = defaultCornerRadius
        clipsToBounds = true

        contentMode = .center

        initSequence()

        addShadow(toLayer: imageView?.layer)
        addShadow(toLayer: titleLabel?.layer)

        // Inserts sublayer after button image is set.
        // Otherwise gradient will cover the image.
        setGradientBackground()
        gradient.colors = gradientColors
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        gradient.frame = bounds
    }

    func setClearBackground() {
        gradient.removeFromSuperlayer()
    }

    func setGradientBackground() {
        layer.insertSublayer(gradient, at: 0)
    }

    func initSequence() {}

}
