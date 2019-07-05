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

fileprivate enum ControlState {
    case normal
    case selected
}

class TabControlView: UIView {

    let borderGradient: CAGradientLayer
    let borderMask: CAShapeLayer

    // Note that UIStackView is a non-rednering view,
    // so it can't draw a background or any other layer added to it.

    let stackView = UIStackView()

    var selectedControl: GradientButton? {
        didSet {
            if let control = oldValue {
                mutate(button: control, to: .normal)
            }
            if let control = selectedControl {
                mutate(button: control, to: .selected)
            }
        }
    }

    override init(frame: CGRect) {
        (borderGradient, borderMask) = makeGradientBorderLayer(colors: defaultGradientColors,
                                                               width: defaultBorderWidth)

        super.init(frame: frame)
        isUserInteractionEnabled = true

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.isUserInteractionEnabled = true
        stackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(stackView)

        layer.cornerRadius = defaultCornerRadius
        layer.cornerRadius = defaultCornerRadius
        layer.addSublayer(borderGradient)
        clipsToBounds = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        borderGradient.frame = bounds
        borderMask.path = UIBezierPath(roundedRect: bounds,
                                       cornerRadius: defaultCornerRadius).cgPath
    }

    func addControl(title: String, _ callback: @escaping () -> Void) {
        let control = createControlButton(title: title)
        stackView.addArrangedSubview(control)

        if selectedControl == .none {
            selectedControl = control
        }

        control.setEventHandler { [unowned self, control] in
            defer {
                callback()
            }

            if let selectedControl = self.selectedControl {
                if selectedControl === control {
                    return
                }
            }

            self.selectedControl = control
        }
    }

}

fileprivate func createControlButton(title: String) -> GradientButton {
    let control = GradientButton()
    control.setTitle(title, for: .normal)
    control.setTitle(title, for: .highlighted)
    control.setTitleColor(.white, for: .normal)
    control.setTitleColor(.white, for: .highlighted)
    control.titleLabel!.font = AvenirFont.demiBold.font(16.0)
    control.layer.cornerRadius = 0.0 // Remove GradientLayer corner radius.
    return control
}

fileprivate func mutate(button: GradientButton, to state:ControlState) {
    switch state {
    case .normal:
        button.setGradientBackground()
    case .selected:
        button.setClearBackground()
    }
}
