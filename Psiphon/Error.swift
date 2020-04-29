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

typealias HashableError = Error & Hashable

struct FatalError: HashableError {
    let message: String
}

/// String representation of a type-erased error.
struct ErrorRepr: HashableError, Codable {
    let repr: String

    static func systemError(_ systemError: SystemError) -> Self {
        return .init(repr: String(describing: systemError))
    }
}

/// Wraps an error event with a localized user description of the error.
/// Note that `ErrorEventDescription` values are equal up to their `event` value only,
/// i.e. `localizedUserDescription` value does not participate in hashValue or equality check.
struct ErrorEventDescription<E: HashableError>: HashableError {
    let event: ErrorEvent<E>
    let localizedUserDescription: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.event == rhs.event
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(event)
    }
}

extension ErrorEventDescription where E: SystemError {

    init(_ event: ErrorEvent<E>) {
        self.event = event
        self.localizedUserDescription = event.error.localizedDescription
    }

}

struct ErrorEvent<E: HashableError>: HashableError {
    let error: E
    let date: Date

    init(_ error: E, date: Date = Date()) {
        self.error = error
        self.date = date
    }

    func map<B: HashableError>(_ f: (E) -> B) -> ErrorEvent<B> {
        return ErrorEvent<B>(f(error), date: date)
    }

    func eraseToRepr() -> ErrorEvent<ErrorRepr> {
        return ErrorEvent<ErrorRepr>(ErrorRepr(repr: String(describing: error)), date: date)
    }

}

extension ErrorEvent: Codable where E: Codable {}

/// Represents an error that originates from Apple frameworks.
/// Although `Error` and `NSError` are bridged, all of our errors will be explicitly tagged as `HashableError`
/// (i.e. `Error & Hashable`).
typealias SystemError = NSError
typealias SystemErrorEvent = ErrorEvent<SystemError>

extension Either: Error where A: Error, B: Error {
    var localizedDescription: String {
        switch self {
        case let .left(error):
            return error.localizedDescription
        case let .right(error):
            return error.localizedDescription
        }
    }
}

extension Array: Error where Element: Error {}
