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

    private let applyCornerRadius: Bool
    private let shadowType: ShadowType?
    private let gradientLayer = CAGradientLayer()
    private let cornerRadius = Style.default.cornerRadius
    
    private var shadowLayer: CAShapeLayer?

    var gradientColors: [CGColor] {
        didSet {
            gradientLayer.colors = gradientColors
        }
    }
    
    override var isEnabled: Bool {
        didSet {
            if isEnabled {
                self.alpha = 1.0
            } else {
                self.alpha = Style.default.disabledButtonAlpha
            }
        }
    }

    init(
        shadow: ShadowType? = .none,
        contentShadow: Bool = false,
        cornerRadius: Bool = true,
        gradient: Gradients
    ) {
        
        self.shadowType = shadow
        self.applyCornerRadius = cornerRadius
        self.gradientColors = gradient.colors

        super.init(frame: .zero)
        
        contentEdgeInsets = UIEdgeInsets(top: 5.0, left: 5.0, bottom: 5.0, right: 5.0)
        
        backgroundColor = UIColor.clear
        contentMode = .center

        initViewBeforeShadowAndGradient()
        
        if contentShadow {
            addShadow(toLayer: imageView?.layer)
            addShadow(toLayer: titleLabel?.layer)
        }
        
        if let shadowType = shadowType {
            shadowLayer = CAShapeLayer()
            shadowLayer!.fillColor = UIColor.clear.cgColor
            shadowLayer!.shadowColor = UIColor.black.cgColor
            shadowLayer!.shadowRadius = 2.0
            shadowLayer!.shadowOffset = CGSize(width: 0.0, height: 2.0)

            switch shadowType {
            case .light:
                shadowLayer!.shadowOpacity = 0.3
            case .strong:
                shadowLayer!.shadowOpacity = 0.84
            }
            
        } else {
            shadowLayer = nil
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
        shadowLayer?.removeFromSuperlayer()
        gradientLayer.removeFromSuperlayer()
        
        if applyCornerRadius {
            // Adds corner radius to layer.
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = true
        } else {
            layer.cornerRadius = 0
            layer.masksToBounds = true
        }
        
    }

    func setGradientBackground() {
        layer.insertSublayer(gradientLayer, at: 0)
        
        if let shadowLayer = shadowLayer {
            layer.insertSublayer(shadowLayer, below: gradientLayer)
        }
        
        if applyCornerRadius {
            
            // Applies corner radius to the gradientLayer.
            // Note that corner radius cannot be added to self.layer since if
            // there is a shadow added, it will get clipped, since
            // layer.masksToBounds must be false for the shadow to render outside
            // the view's bounds.
            gradientLayer.cornerRadius = cornerRadius
            layer.masksToBounds = false
            
        } else {
            layer.cornerRadius = 0
            layer.masksToBounds = true
        }
        
    }

    /// Subclasses should override this function when initializing and adding their own subviews and layers.
    /// This method is called as part of `GradientButton` init function.
    func initViewBeforeShadowAndGradient() {}

}
