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

    func build(_ container: UIView?) -> StrictBindableViewable<Bool, UIActivityIndicatorView> {
        let spinner = UIActivityIndicatorView(style: self.style)
        return .init(viewable: spinner) { spinner -> ((Bool) -> Void) in
            return { animate in
                if animate {
                    spinner.startAnimating()
                } else {
                    spinner.stopAnimating()
                }
            }
        }
    }

}
