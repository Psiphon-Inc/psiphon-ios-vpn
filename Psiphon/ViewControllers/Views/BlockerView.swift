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

/// Builds a view meant to block the screen and display a spinner with some message or a button if desired.
struct BlockerView: ViewBuilder {
    
    // Wrapper around a handler closure.
    // This class is necessary since a ViewBuilder's BindingType
    // should be equatable.
    final class Handler: Equatable {

        private let handler: () -> Void
        
        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }
        
        static func == (lhs: Handler, rhs: Handler) -> Bool {
            lhs === rhs
        }
        
        func callAsFunction() -> Void {
            handler()
        }
        
    }
    
    struct DisplayOption: Equatable {
        
        struct ButtonOption: Equatable {
            let title: String
            let handler: Handler
        }
        
        enum ViewOptions: Equatable {
            case label(text: String)
            case labelAndButton(labelText: String, buttonOptions: [ButtonOption])
        }
        
        let animateSpinner: Bool
        let viewOptions: ViewOptions
        
    }
    
    func build(_ container: UIView?) -> ImmutableBindableViewable<DisplayOption, UIView> {
        
        let background = UIView(frame: .zero)
        background.backgroundColor = .darkGray2()
        
        let vStack = UIStackView.make(
            axis: .vertical,
            distribution: .equalSpacing,
            alignment: .center,
            spacing: Style.default.padding
        )
        
        let spinner = UIActivityIndicatorView(style: .whiteLarge)
        spinner.tag = 1
        
        let label = UILabel.make(
            fontSize: .normal,
            typeface: .medium,
            color: .white,
            numberOfLines: 0,
            alignment: .center
        )
        label.tag = 2
        
        // Adds permanent views
        background.addSubview(vStack)
        
        vStack.addArrangedSubviews(
            spinner,
            label
        )
        
        // Setup Auto Layout
        vStack.activateConstraints {
            $0.constraintToParent(.centerX(), .centerY())
        }
        
        return .init(viewable: background) { [vStack, label] _ in
            
            return { displayOption in
                
                if displayOption.animateSpinner {
                    spinner.isHidden = false
                    spinner.startAnimating()
                } else {
                    spinner.isHidden = true
                    spinner.stopAnimating()
                }
                
                switch displayOption.viewOptions {
                case let .label(text: text):
                    
                    // Removes all buttons if any.
                    vStack.subviews.forEach {
                        if $0.tag == 3 /* button's tag */ {
                            vStack.removeArrangedSubview($0)
                            $0.removeFromSuperview()
                        }
                    }
                    
                    label.text = text
                    
                case let .labelAndButton(labelText: text, buttonOptions: buttonOptions):
                    
                    label.text = text
                    
                    // Removes all previous buttons if any.
                    vStack.subviews.forEach {
                        if $0.tag == 3 /* button's tag */ {
                            vStack.removeArrangedSubview($0)
                            $0.removeFromSuperview()
                        }
                    }
                    
                    // Adds the new buttons.
                    for option in buttonOptions {
                        let button = SwiftUIButton(type: .system)
                        button.tag = 3
                        vStack.addArrangedSubviews(button)
                        button.setTitle(option.title, for: .normal)
                        button.setEventHandler {
                            option.handler()
                        }
                    }
                    
                }
            }
        }
        
    }
    
}
