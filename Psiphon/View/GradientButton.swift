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
    
    @objc enum ShadowType: Int {
        case light
        case strong
    }

    private let shadowLayer: CAShapeLayer?
    private let gradientLayer = CAGradientLayer()
    
    private let cornerRadius = Style.default.cornerRadius

    var gradientColors: [CGColor] {
        didSet {
            gradientLayer.colors = gradientColors
        }
    }

    init(shadow: ShadowType? = .none, contentShadow: Bool = false, gradient: Gradients) {
        
        // Adds shadow layer to self, if content also get a shadow.
        if let shadow = shadow {
            shadowLayer = CAShapeLayer()
            shadowLayer!.fillColor = UIColor.clear.cgColor
            shadowLayer!.shadowColor = UIColor.black.cgColor
            shadowLayer!.shadowRadius = 2.0
            shadowLayer!.shadowOffset = CGSize(width: 0.0, height: 2.0)

            switch shadow {
            case .light:
                shadowLayer!.shadowOpacity = 0.3
            case .strong:
                shadowLayer!.shadowOpacity = 0.84
            }
            
        } else {
            shadowLayer = nil
        }
        
        gradientColors = gradient.colors

        super.init(frame: .zero)
        
        contentEdgeInsets = UIEdgeInsets(top: 5.0, left: 5.0, bottom: 5.0, right: 5.0)
        
        backgroundColor = UIColor.clear
        contentMode = .center

        initViewBeforeShadowAndGradient()

        // Note that currently shadow is tied to layer.masksToBounds,
        // since whenever shadows are not used, it is desired for layer.masksToBounds
        // to be true (e.g. PsiCashViewController tab buttons.)
        // If shadow is set, then corner radius is added to the gradientLayer,
        // otherwise corner radius is added to view's main layer.
        
        if shadow != nil {
            gradientLayer.cornerRadius = cornerRadius
        } else {
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = true
        }
        
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
        
        if let shadowLayer = shadowLayer {
            shadowLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
            shadowLayer.shadowPath = shadowLayer.path
        }
        
    }

    func setClearBackground() {
        gradientLayer.removeFromSuperlayer()
    }

    func setGradientBackground() {
        layer.insertSublayer(gradientLayer, at: 0)
        
        if let shadowLayer = shadowLayer {
            layer.insertSublayer(shadowLayer, below: gradientLayer)
        }
    }

    /// Subclasses should override this function when initializing and adding their own subviews and layers.
    /// This method is called as part of `GradientButton` init function.
    func initViewBeforeShadowAndGradient() {}

}
