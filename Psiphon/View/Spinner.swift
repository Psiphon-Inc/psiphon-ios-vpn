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

struct Spinner: ViewBuilder {
    let style: UIActivityIndicatorView.Style

    init(style: UIActivityIndicatorView.Style = .white) {
        self.style = style
    }

    // The spinner view needs to be wrapped inside another view so that it can be centred.
    // Instead of wrapping the spinner inside a new wrapper UIView with a ImmutableBindableViewable,
    // we can instead reuse the container view that's passed in with a MutableBindableViewable.
    
    func build(_ container: UIView?) -> MutableBindableViewable<Bool, UIActivityIndicatorView> {
        
        // container will always be passed in for a MutableBindableViewable.
        guard let container = container else {
            fatalError()
        }
        
        let spinner = UIActivityIndicatorView(style: self.style)
        
        container.addSubview(spinner)
        
        spinner.activateConstraints {
            $0.constraintToParent(.centerX(), .centerY()) + [
                container.widthAnchor.constraint(greaterThanOrEqualTo: $0.widthAnchor),
                container.heightAnchor.constraint(greaterThanOrEqualTo: $0.heightAnchor)
            ]
        }
        
        return .init(viewable: spinner) { spinner -> ((Bool) -> UIActivityIndicatorView?) in
            return { animate in
                // viewable will always be passed in for a MutableBindableViewable.
                guard let spinner = spinner else {
                    fatalError()
                }
                if animate {
                    spinner.startAnimating()
                } else {
                    spinner.stopAnimating()
                }
                return spinner
            }
        }
    }

}
