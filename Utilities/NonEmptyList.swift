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

public struct NonEmpty<Element> {
    private var storage: [Element]

    public init(_ head: Element, _ tail: [Element]) {
        self.storage = [head] + tail
    }

    public init?(array: [Element]?) {
        guard let array = array else {
            return nil
        }
        guard array.count > 0 else {
            return nil
        }
        self.storage = array
    }
    
    public var head: Element {
        self.storage.first!
    }
    
    public var tail: ArraySlice<Element> {
        self.storage.dropFirst()
    }

    public var count: Int {
        self.storage.count
    }

    public subscript(index: Int) -> Element {
        get {
            self.storage[index]
        }
        set(newValue) {
            self.storage[index] = newValue
        }
    }

}

extension NonEmpty: Equatable where Element: Equatable {
    
    public func isEqual(_ array: [Element]) -> Bool {
        return self.storage == array
    }
    
}
extension NonEmpty: Hashable where Element: Hashable {}

extension NonEmpty: Collection {
    public func index(after i: Int) -> Int { self.storage.index(after: i) }

    public var startIndex: Int { self.storage.startIndex }

    public var endIndex: Int { self.storage.endIndex }
}
