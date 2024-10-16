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

public enum NonEmptySeq<T> {
    case elem(T)
    indirect case cons(T, NonEmptySeq<T>)
}

extension NonEmptySeq {
    public mutating func append(x: T) -> NonEmptySeq<T> {
        switch self {
        case .elem(let y):
            return .cons(y, .elem(x))
        case .cons(let y, var ys):
            return .cons(y, ys.append(x: x))
        }
    }

    public mutating func prepend(x: T) -> NonEmptySeq<T> {
        switch self {
        case .elem(let y):
            return .cons(x, .elem(y))
        case .cons(let y, let ys):
            return .cons(x, .cons(y, ys))
        }
    }
}

enum NonEmptySeqCodingError: Error {
    case coding(String)
    case decoding(String)
}

extension NonEmptySeq: Equatable where T: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.elem(let x), .elem(let y)):
            return x == y
        case (.cons(let x, let xs), .cons(let y, let ys)):
            return x == y && xs == ys
        case (.elem(_), .cons(_,_)):
            return false
        case (.cons(_, _), .elem(_)):
            return false
        }
    }
}

extension NonEmptySeq: Codable where T: Codable {

    private enum CodingKeys: String, CodingKey {
        case elem = "elem"
        case cons = "cons"
    }

    private struct ConsTuple<U: Codable>: Codable {
        let elem: U
        let cons: NonEmptySeq<U>

        init(elem: U, cons: NonEmptySeq<U>) {
            self.elem = elem
            self.cons = cons
        }

        private enum CodingKeys: String, CodingKey {
            case elem = "x"
            case cons = "xs"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .elem(let x):
            try container.encode(x, forKey: .elem)
        case .cons(let x, let xs):
            try container.encode(ConsTuple<T>(elem: x, cons: xs), forKey: .cons)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? values.decode(T.self, forKey: .elem) {
            self = .elem(value)
            return
        }
        if let value = try? values.decode(ConsTuple<T>.self, forKey: .cons) {
            self = .cons(value.elem, value.cons)
            return
        }
        throw NonEmptySeqCodingError.decoding("Failed to decode non-empty list from: \(dump(values))")
    }

}
