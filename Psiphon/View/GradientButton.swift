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

    private let gradientLayer = CAGradientLayer()

    var gradientColors: [CGColor] {
        didSet {
            gradientLayer.colors = gradientColors
        }
    }

    init(addContentShadow contentShadow: Bool = false, gradient: Gradients) {
        gradientColors = gradient.colors

        super.init(frame: .zero)

        backgroundColor = UIColor.clear
        layer.cornerRadius = Style.default.cornerRadius
        clipsToBounds = true

        contentMode = .center

        initViewBeforeShadowAndGradient()

        if contentShadow {
            addShadow(toLayer: imageView?.layer)
            addShadow(toLayer: titleLabel?.layer)
        }

        // Inserts sublayer after initSequence is called where image might be set.
        // Otherwise gradient will cover the image.
        setGradientBackground()
        gradientLayer.colors = gradientColors
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setImage(_ image: UIImage?, for state: UIControl.State) {
        // First remove the gradient layer, otherwise it masks the image.
        setClearBackground()
        super.setImage(image, for: state)
        setGradientBackground()

        // Apply some defaults
        imageView!.contentMode = .scaleAspectFit
        imageEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 4.0)
    }

    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        gradientLayer.frame = bounds
    }

    func setClearBackground() {
        gradientLayer.removeFromSuperlayer()
    }

    func setGradientBackground() {
        layer.insertSublayer(gradientLayer, at: 0)
    }

    /// Subclasses should override this function when initializing and adding their own subviews and layers.
    /// This method is called as part of `GradientButton` init function.
    func initViewBeforeShadowAndGradient() {}

}
