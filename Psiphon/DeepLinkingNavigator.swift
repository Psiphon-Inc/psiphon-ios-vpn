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

struct DeepLinkingNavigator {
    
    private var registered: [URL: () -> Bool] = [:]
    
    mutating func register(urls: [URL], completionHandler: @escaping () -> Bool) {
        for url in urls {
            registered[url] = completionHandler
        }
    }
    
    func handle(url: URL) -> Bool {
        if let handler = registered[url] {
            return handler()
        }
        return false
    }
    
}
