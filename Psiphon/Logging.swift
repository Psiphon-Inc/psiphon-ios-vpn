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

protocol FeedbackDescription {}

protocol CustomFeedbackDescription {
    var feedbackFields: [String: CustomStringConvertible] { get }
}

extension CustomFeedbackDescription {
    /// Default description for `CustomFeedbackDescription`.
    ///
    /// For example, given the following struct
    /// ```
    /// struct SomeValue: CustomFeedbackDescription {
    ///     let string: String
    ///     let float: Float
    ///
    ///     var feedbackFields: [String: CustomStringConvertible] {
    ///         ["float": float]
    ///     }
    /// }
    /// ```
    /// The following  value would have the following description:
    /// ```
    /// let value = SomeValue(string: "string", float: 3.14)
    /// value.description == "SomeValue([\"float\": 3.14])"
    /// ```
    var description: String {
        "\(String(describing: Self.self))(\(String(describing: feedbackFields))"
    }
}

typealias LogTag = String

enum LogLevel: Int {
    case info
    case warn
    case error
}

struct LogMessage: ExpressibleByStringLiteral, Equatable, CustomStringConvertible {
    typealias StringLiteralType = String
    
    private var value: String
    
    public init(stringLiteral value: String) {
        self.value = value
    }
    
    public var description: String {
        return self.value
    }
}

func feedbackLog(_ level: LogLevel, tag: LogTag, _ message: LogMessage) -> Effect<Never> {
    .fireAndForget {
        switch level {
        case .info:
            PsiFeedbackLogger.info(withType: tag, message: message.description)
        case .warn:
            PsiFeedbackLogger.warn(withType: tag, message: message.description)
        case .error:
            PsiFeedbackLogger.error(withType: tag, message: message.description)
        }
    }
}

func feedbackLog<T: FeedbackDescription>(
    _ level: LogLevel, tag: LogTag = "message", _ value: T
) -> Effect<Never> {
    .fireAndForget {
        let message = String(describing: value)
        switch level {
        case .info:
            PsiFeedbackLogger.info(withType: tag, message: message)
        case .warn:
            PsiFeedbackLogger.warn(withType: tag, message: message)
        case .error:
            PsiFeedbackLogger.error(withType: tag, message: message)
        }
    }
}

func feedbackLog<T: CustomFeedbackDescription>(
    _ level: LogLevel, tag: LogTag = "message",  _ value: T
) -> Effect<Never> {
    .fireAndForget {
        switch level {
        case .info:
            PsiFeedbackLogger.info(withType: tag, message: value.description)
        case .warn:
            PsiFeedbackLogger.warn(withType: tag, message: value.description)
        case .error:
            PsiFeedbackLogger.error(withType: tag, message: value.description)
        }
    }
}
