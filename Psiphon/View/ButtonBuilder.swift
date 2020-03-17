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

import UIKit

struct ButtonBuilder: ViewBuilder {
    let style: UIButton.ButtonType
    let tint: UIColor?
    let image: UIImage?
    let eventHandler: (() -> Void)?

    func build(_ container: UIView?) -> StrictBindableViewable<Unit, SwiftUIButton> {
        let button = SwiftUIButton(type: style)
        if let tint = tint {
            button.tintColor = tint
        }
        if let image = image {
            button.setImage(image, for: .normal)
        }
        if let eventHandler = eventHandler {
            button.setEventHandler(eventHandler)
        }
        return .init(viewable: button) { _ -> ((Unit) -> Void) in
            return { _ in }
        }
    }

}
