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

import Foundation

/// Wraps a single view. ContainerView allows for easily adding background
/// or padding to any view.
final class ContainerView<Wrapped: UIView>: UIView {
    
    private let backgroundLayers: [CALayer]
    private let layersUpdateFunc: ([CALayer], CGRect) -> Void
    
    var wrappedView: Wrapped {
        self.subviews[0] as! Wrapped
    }
    
    /// Adds `containedView` as a subview of current view.
    init(
        wraps wrappedView: Wrapped,
        backgroundColor: UIColor? = nil,
        backgroundLayers: () -> (layers: [CALayer], layerUpdate: ([CALayer], CGRect) -> Void),
        cornerRadius: CGFloat = 0.0,
        clipsToBounds: Bool = true,
        padding: Padding = Padding()
        ) {
        
        (self.backgroundLayers, self.layersUpdateFunc) = backgroundLayers()
        
        super.init(frame: .zero)
        
        self.backgroundColor = backgroundColor
        
        self.backgroundLayers.forEach {
            self.layer.addSublayer($0)
        }
        
        self.addSubview(wrappedView)
                    
        wrappedView.activateConstraints {
            $0.constraintToParent(
                .top(padding.top, .required),
                .bottom(-padding.bottom, .required),
                .leading(padding.leading, .required),
                .trailing(-padding.trailing, .required)
            )
        }
        
        self.layer.cornerRadius = cornerRadius
        self.clipsToBounds = clipsToBounds
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        self.layersUpdateFunc(self.backgroundLayers, self.bounds)
    }
    
}

extension ContainerView {
    
    static func makePaddingContainer(
        wraps wrappedView: Wrapped,
        backgroundColor: UIColor? = nil,
        padding: Padding
    ) -> ContainerView<Wrapped> {
        .init(
            wraps: wrappedView,
            backgroundColor: backgroundColor,
            backgroundLayers: { () -> (layers: [CALayer], layerUpdate: ([CALayer], CGRect) -> Void) in
                (layers: [], layerUpdate: { _, _ in })
            },
            cornerRadius: 0.0,
            clipsToBounds: false,
            padding: padding
        )
    }
    
    static func makeGradientBackground(
        wraps wrappedView: Wrapped,
        cornerRadius: CGFloat = Style.default.cornerRadius,
        borderWidth: CGFloat = Style.default.borderWidth,
        gradientColours: [CGColor] = Gradients.blue.colors,
        padding: Padding = Padding()
    ) -> ContainerView<Wrapped> {
        .init(
            wraps: wrappedView,
            backgroundLayers: { () -> (layers: [CALayer], layerUpdate: ([CALayer], CGRect) -> Void) in
                
                let borderMask = CAShapeLayer()
                mutate(borderMask) {
                    $0.lineWidth = borderWidth
                    $0.fillColor = nil
                    $0.strokeColor = UIColor.black.cgColor
                }
                
                let gradient = CAGradientLayer()
                mutate(gradient) {
                    $0.startPoint = CGPoint(x: 0.5, y: 0.0)
                    $0.endPoint = CGPoint(x: 0.5, y: 1.0)
                    $0.colors = gradientColours
                    $0.mask = borderMask
                }
                
                return (
                    layers: [gradient],
                    layerUpdate: { layers , bounds in
                        guard let gradientLayer = layers[maybe: 0] else {
                            fatalError()
                        }
                        gradientLayer.frame = bounds
                        (gradientLayer.mask! as! CAShapeLayer).path = UIBezierPath(
                            roundedRect: bounds,
                            cornerRadius: cornerRadius
                        ).cgPath
                    })
                
            },
            cornerRadius: cornerRadius,
            clipsToBounds: true,
            padding: padding)
    }
    
}
