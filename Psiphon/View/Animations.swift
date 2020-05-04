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

enum ShrinkAnimationType {
    case shrink
    case restore
}

func animateShrink(_ type: ShrinkAnimationType, _ view: UIView) {
    UIView.animate(withDuration: 0.1) {
        switch type {
        case .shrink:
            view.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            view.alpha = 0.9
        case .restore:
            view.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            view.alpha = 1.0
        }
    }
}
