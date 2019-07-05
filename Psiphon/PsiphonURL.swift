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

struct Bindable<Value> {
    private let value: Value

    init(_ value: Value) {
        self.value = value
    }

    func map(_ transformer: (Value) -> Bindable<Value>) -> Bindable<Value> {
        return transformer(value)
    }
}

extension Bindable where Value == URL {

    func getURL(_ vpnState: NEVPNStatus?) -> URL? {
        switch vpnState {
        case .connected:
            return value
        default:
            return nil
        }
    }

}

typealias RestrictedURL = Bindable<URL>
