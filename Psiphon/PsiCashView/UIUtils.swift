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

import Foundation

let defaultBorderWidth: CGFloat = 5.0
let defaultCornerRadius: CGFloat = 8.0
let defaultGradientColors = [UIColor.lightishBlue(), UIColor.lightRoyalBlueTwo()].cgColors


enum AvenirFont: String {
    case medium = "AvenirNext-Medium"
    case demiBold = "AvenirNext-DemiBold"
    case bold = "AvenirNext-Bold"

    func font(_ size: CGFloat = 14.0) -> UIFont {
        return UIFont(name: self.rawValue, size: size)!
    }
}


func makeLabel(
    text: String = "",
    fontSize: CGFloat = 13.0,
    typeface: AvenirFont = .demiBold,
    color: UIColor = .white)
    -> UILabel {
    let v = UILabel()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = .clear
    v.adjustsFontSizeToFitWidth = true
    v.minimumScaleFactor = 0.6
    v.numberOfLines = 1
    v.font = typeface.font(fontSize)
    v.textAlignment = .natural
    v.textColor = color
    v.isUserInteractionEnabled = false
    v.clipsToBounds = true
    v.text = text
    return v
}


/// Sets `translatesAutoresizingMaskIntoConstraints` to false for each child of given view.
func setChildrenAutoresizingMaskIntoConstraintsFlagToFalse(forView view: UIView) {
    view.subviews.forEach {
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
}


/// Backwards compatible safe area layout guide.
func addBackwardsCompatibleSafeAreaLayoutGuide(to view: UIView) -> UILayoutGuide {
    let layoutGuide = UILayoutGuide()
    view.addLayoutGuide(layoutGuide)

    if #available(iOS 11.0, *) {
        NSLayoutConstraint.activate([
            layoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            layoutGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            layoutGuide.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            layoutGuide.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

    } else {
        // Fallback on earlier versions
        NSLayoutConstraint.activate([
            layoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
            layoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            layoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    return layoutGuide
}


func addShadow(toLayer layer: CALayer?) {
    guard let layer = layer else {
        return
    }

    guard !(layer is CATransformLayer) else {
        fatalError("Cannot add shadow to CATransformLayer")
    }

    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
    layer.shadowOpacity = 0.22
    layer.shadowRadius = 2.0
}

/// Should set frame on returned `CAGradientLayer` and set path on returned `CAShapeLayer`.
func makeGradientBorderLayer(colors: [CGColor], width: CGFloat = 2.0)
    -> (CAGradientLayer, CAShapeLayer) {
    let gradient = CAGradientLayer()
    gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
    gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
    gradient.colors = colors

    let borderMask = CAShapeLayer()
    borderMask.lineWidth = width
    borderMask.fillColor = nil
    borderMask.strokeColor = UIColor.black.cgColor
    gradient.mask = borderMask

    return (gradient, borderMask)
}

func setBackgroundGradient(for view: UIView) {
    guard view.bounds.size != CGSize.zero else {
        preconditionFailure("view bounds not set")
    }

    let backgroundGradient = CAGradientLayer()
    backgroundGradient.colors = [UIColor.lightNavy().cgColor,
                                 UIColor.darkNavy().cgColor]

    backgroundGradient.frame = view.bounds
    backgroundGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
    backgroundGradient.endPoint = CGPoint(x: 0.5, y: 0.33)

    view.layer.insertSublayer(backgroundGradient, at: 0)
}

extension Array where Element == UIColor {

    var cgColors: [CGColor] {
        return self.map { $0.cgColor }
    }

}
