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

final class TabControlView<Tabs: UICases>: UIView, Bindable {

    let borderGradient: CAGradientLayer
    let borderMask: CAShapeLayer

    // Note that UIStackView is a non-rendering view,
    // so it can't draw a background or any other layer added to it.

    let stackView = UIStackView()
    var controlButtons: [Tabs: GradientButton]

    private var selectedControl: GradientButton? {
        didSet {
            if let control = oldValue {
                mutate(button: control, to: .normal)
            }
            if let control = selectedControl {
                mutate(button: control, to: .selected)
            }
        }
    }

    init() {
        self.controlButtons = [:]
        (borderGradient, borderMask) = makeGradientBorderLayer(colors: Gradients.blue.colors,
                                                               width: Style.default.borderWidth)

        super.init(frame: .zero)

        // Add the controls
        for tab in Tabs.allCases {
            let control = createControlButton(title: tab.description)
            stackView.addArrangedSubview(control)
            self.controlButtons[tab] = control
        }

        isUserInteractionEnabled = true

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.isUserInteractionEnabled = true
        stackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(stackView)

        layer.cornerRadius = Style.default.cornerRadius
        layer.cornerRadius = Style.default.cornerRadius
        layer.addSublayer(borderGradient)
        clipsToBounds = true
    }

    required init(coder: NSCoder) {
        fatalErrorFeedbackLog("init(coder:) has not been implemented")
    }

    func bind(_ newValue: Tabs) {
        self.selectedControl = self.controlButtons[newValue]
    }

    func setTabHandler(_ handler: @escaping (Tabs) -> Void) {
        for tab in Tabs.allCases {
            self.controlButtons[tab]!.setEventHandler {
                handler(tab)
            }
        }
    }

    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        borderGradient.frame = bounds
        borderMask.path = UIBezierPath(roundedRect: bounds,
                                       cornerRadius: Style.default.cornerRadius).cgPath
    }

}

fileprivate func createControlButton(title: String) -> GradientButton {
    let control = GradientButton(gradient: .blue)
    control.setTitle(title, for: .normal)
    control.setTitle(title, for: .highlighted)
    control.setTitleColor(.white, for: .normal)
    control.setTitleColor(.white, for: .highlighted)
    control.titleLabel!.font = AvenirFont.demiBold.font(.h3)
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
