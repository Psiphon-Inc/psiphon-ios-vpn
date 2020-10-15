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
import protocol PsiApi.LocalizedUserDescription

fileprivate enum ControlState {
    case normal
    case selected
}

typealias TabControlViewTabType = Hashable & CaseIterable & LocalizedUserDescription

final class TabControlViewWrapper<Tabs: TabControlViewTabType>: ViewWrapper, Bindable {

    // Note that UIStackView is a non-rendering view,
    // so it can't draw a background or any other layer added to it.

    let wrapperView: UIView
    var controlButtons = [Tabs: GradientButton]()
    
    var view: UIView {
        wrapperView
    }

    private var selectedControl: GradientButton? {
        didSet {
            if let control = oldValue {
                setBackgroundColor(button: control, to: .normal)
            }
            if let control = selectedControl {
                setBackgroundColor(button: control, to: .selected)
            }
        }
    }

    init() {
        let cornerRadius = Style.default.cornerRadius
                
        let stackView = UIStackView.make(
            axis: .horizontal,
            distribution: .fillEqually
        )
        
        self.wrapperView = ContainerView.makeGradientBackground(
            wraps: stackView,
            cornerRadius: cornerRadius)
                
        self.wrapperView.activateConstraints {
            $0.constraint(to: stackView, .width(.belowRequired), .height(.belowRequired))
        }
        
        mutate(stackView) {
            $0.isUserInteractionEnabled = true
        }
        
        stackView.activateConstraints {
            $0.constraintToParent(.leading(), .top()) + [
                // Height constraint can be broken when the view is hidden.
                // In current implementation, it is the UIStackView that hides the views.
                $0.heightAnchor.constraint(equalToConstant: Style.default.buttonHeight)
                    .priority(.belowRequired)
            ]
        }
        
        // Add the controls
        for tab in Tabs.allCases {
            let control = createControlButton(title: tab.localizedUserDescription)
            stackView.addArrangedSubview(control)
            self.controlButtons[tab] = control
        }
        
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
    
}

fileprivate func createControlButton(title: String) -> GradientButton {
    let control = GradientButton(gradient: .blue)
    control.setTitle(title, for: .normal)
    control.setTitle(title, for: .highlighted)
    control.setTitleColor(.white, for: .normal)
    control.setTitleColor(.white, for: .highlighted)
    control.titleLabel!.font = AvenirFont.demiBold.font(.h3)
    control.layer.cornerRadius = 0.0 // Remove GradientLayer corner radius.
    control.setClearBackground()
    return control
}

fileprivate func setBackgroundColor(button: GradientButton, to state:ControlState) {
    switch state {
    case .normal:
        button.setClearBackground()
    case .selected:
        button.setGradientBackground()
    }
}
