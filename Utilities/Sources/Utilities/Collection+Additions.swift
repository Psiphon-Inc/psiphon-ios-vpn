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

extension Array {
    
    /// Divides an array into two slices where the collection satisfies the `predicate`.
    /// - Returns: `[]` if there are no elements in the collection, or `[self]` if predicate is never satisfied.
    /// Otherwise, returns two slices `[firstSlice, secondSlice]`, where `secondSlice` contains
    /// the element for which `predicate` returned `true`.
    public func slice(atFirstOccurrence predicate: (Element) -> Bool) -> [ArraySlice<Element>] {
        guard count > 0 else {
            return []
        }
        
        guard let index = firstIndex(where: predicate) else {
            return [self[...]]
        }
        
        return [self[..<index], self[index...]]
    }
    
}
