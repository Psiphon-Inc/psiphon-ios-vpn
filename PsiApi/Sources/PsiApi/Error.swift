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
import struct NetworkExtension.NEVPNError
import struct StoreKit.SKError

public typealias HashableError = Error & Hashable

public struct FatalError: HashableError {
    public let message: LogMessage
    
    public init(_ message: LogMessage) {
        self.message = message
    }
}

/// String representation of a type-erased error.
public struct ErrorRepr: HashableError, Codable {

    let repr: String

    public init(repr: String) {
        self.repr = repr
    }
    
    public static func systemError<Code>(_ systemError: SystemError<Code>) -> Self {
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

/// Represents an `NSError`.
///
/// `Code` in practice should either be an `Int` or a `RawRepresentable` type with `RawValue == Int`.
///
/// Additionally, in the current implementation of `SystemError`,
/// the underlying type has `Code == Int`.
/// 
/// A more complete description of `SystemError` would require it to be some kind of a
/// recursive type, so far however this level of type information has not been needed.
///
public enum SystemError<Code: Hashable>: HashableError {

    /// Represents root error cause of an error condition.
    case rootError(ErrorInfo)

    /// Represents an error condition with an underlying error.
    indirect case error(ErrorInfo, underlyingError: SystemError<Int>)

    /// Wraps values from an `NSError` object that we care about.
    public struct ErrorInfo: HashableError {
        /// Error domain.
        public let domain: String
        /// Typed error code for the given domain.
        public let code: Code
        /// Integral error code for the given domain.
        public let errorCode: Int
        /// Localized description of an `NSError`.
        public let localizedDescription: String?
        /// Localized failure reason of an `NSError`.
        public let localizedFailureReason: String?
    }

    /// Returns `ErrorInfo` object of the top error.
    public var errorInfo: ErrorInfo {

        switch self {

        case .rootError(let errorInfo):
            return errorInfo

        case .error(let errorInfo, underlyingError: _):
            return errorInfo

        }

    }

}

public extension SystemError {

    static func make(_ nsError: NSError) -> SystemError<Int> {

        let errorInfo = SystemError<Int>.ErrorInfo(
            domain: nsError.domain,
            code: nsError.code,
            errorCode: nsError.code,
            localizedDescription: nsError.localizedDescription,
            localizedFailureReason: nsError.localizedFailureReason
        )

        let maybeUnderlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError

        if let underlyingError = maybeUnderlyingError {
            return .error(errorInfo, underlyingError: .make(underlyingError))
        } else {
            return .rootError(errorInfo)
        }

    }

    static func make(_ nsError: NEVPNError) -> SystemError<NEVPNError.Code> {

        let errorInfo = SystemError<NEVPNError.Code>.ErrorInfo(
            domain: NEVPNError.errorDomain,
            code: nsError.code,
            errorCode: nsError.errorCode,
            localizedDescription: nsError.localizedDescription,
            localizedFailureReason: nil
        )

        let maybeUnderlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError

        if let underlyingError = maybeUnderlyingError {
            return .error(errorInfo, underlyingError: .make(underlyingError))
        } else {
            return .rootError(errorInfo)
        }

    }

    static func make(_ nsError: SKError) -> SystemError<SKError.Code> {

        let errorInfo = SystemError<SKError.Code>.ErrorInfo(
            domain: SKError.errorDomain,
            code: nsError.code,
            errorCode: nsError.errorCode,
            localizedDescription: nsError.localizedDescription,
            localizedFailureReason: nil
        )

        let maybeUnderlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError

        if let underlyingError = maybeUnderlyingError {
            return .error(errorInfo, underlyingError: .make(underlyingError))
        } else {
            return .rootError(errorInfo)
        }

    }

}

public typealias SystemErrorEvent<Code: Hashable> = ErrorEvent<SystemError<Code>>

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
