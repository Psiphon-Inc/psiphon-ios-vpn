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
import Utilities

public typealias HashableError = Error & Hashable

public struct FatalError: HashableError {
    let message: String
}

/// String representation of a type-erased error.
public struct ErrorRepr: HashableError, Codable {
    let repr: String

    public init(repr: String) {
        self.repr = repr
    }
    
    public static func systemError(_ systemError: SystemError) -> Self {
        return .init(repr: String(describing: systemError))
    }
}

/// Wraps an error event with a localized user description of the error.
/// Note that `ErrorEventDescription` values are equal up to their `event` value only,
/// i.e. `localizedUserDescription` value does not participate in hashValue or equality check.
public struct ErrorEventDescription<E: HashableError>: HashableError {
    public let event: ErrorEvent<E>
    public let localizedUserDescription: String

    public init(event: ErrorEvent<E>, localizedUserDescription: String) {
        self.event = event
        self.localizedUserDescription = localizedUserDescription
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.event == rhs.event
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(event)
    }
}

extension ErrorEventDescription where E == SystemError {

    public init(_ event: ErrorEvent<E>) {
        self.event = event
        self.localizedUserDescription = event.error.localizedDescription
    }

}

public struct ErrorEvent<E: HashableError>: HashableError, FeedbackDescription {
    public let error: E
    public let date: Date

    public init(_ error: E, date: Date = Date()) {
        self.error = error
        self.date = date
    }

    public func map<B: HashableError>(_ f: (E) -> B) -> ErrorEvent<B> {
        return ErrorEvent<B>(f(error), date: date)
    }

    public func eraseToRepr() -> ErrorEvent<ErrorRepr> {
        return ErrorEvent<ErrorRepr>(ErrorRepr(repr: String(describing: error)), date: date)
    }

}

extension ErrorEvent: Codable where E: Codable {}

/// `SystemError` represents an error that originates from Apple frameworks (i.e. constructed from NSError).
public struct SystemError: HashableError {
    let domain: String
    let code: Int
    
    init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
    
    public init(_ nsError: NSError) {
        self.domain = nsError.domain
        self.code = nsError.code
    }
    
    public init(_ error: Error) {
        let nsError = error as NSError
        self.domain = nsError.domain
        self.code = nsError.code
    }
}

public typealias SystemErrorEvent = ErrorEvent<SystemError>

extension Either: Error where A: Error, B: Error {
    public var localizedDescription: String {
        switch self {
        case let .left(error):
            return error.localizedDescription
        case let .right(error):
            return error.localizedDescription
        }
    }
}

//extension Array: Error where Element: Error {}

public protocol ErrorUserDescription where Self: Error {
    
    /// User-facing description of error.
    var userDescription: String { get }
    
}

public typealias CodableError = Codable & Error

public struct ScopedError<T: Error>: Error {
    let err: T
    let file: String
    let line: UInt

    public init(err: T, file: String = #file, line: UInt = #line) {
        self.err = err
        self.file = file
        self.line = line
    }
}

extension ScopedError: Codable where T: Codable {
    
    private enum CodingKeys: String, CodingKey {
        case err = "error"
        case file = "file"
        case line = "line"
    }

}

public typealias NestedScopedError<T: CodableError> = NonEmptySeq<ScopedError<T>>
