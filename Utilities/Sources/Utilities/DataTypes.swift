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

/// Represents unit `()` type that is `Equatable`.
/// - Bug: This is a hack since `()` (and generally tuples) do not conform to `Equatable`.
public enum Unit: Equatable {
    case unit
}

/// A 2-tuple, useful for when the tuple type can't be used.
public struct Pair<A, B> {
    public let first: A
    public let second: B
    
    public init(first: A, second: B) {
        self.first = first
        self.second = second
    }
}

extension Pair: Equatable where A: Equatable, B: Equatable {}

public enum Either<A, B> {
    case left(A)
    case right(B)
}

extension Either: Equatable where A: Equatable, B: Equatable {}
extension Either: Hashable where A: Hashable, B: Hashable {}

public extension Either {

    /// If `A` and `B` are not `Equatable`, we can at least check equality of `self` and  provided `value`
    /// ignoring the associated value.
    func isEqualCase(_ value: Either<A, B>) -> Bool {
        switch (self, value) {
        case (.left, .left):
            return true
        case (.right, .right):
            return true
        default:
            return false
        }
    }
}
