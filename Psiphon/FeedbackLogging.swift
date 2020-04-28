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

protocol CustomStringFeedbackDescription: FeedbackDescription, CustomStringConvertible {}

/// `NSObject` classes should not adopt this protocol, since the default  `NSObject.description` function
/// will be called instead of the default description value provided by this protocol.
protocol CustomFieldFeedbackDescription: FeedbackDescription, CustomStringConvertible {
    var feedbackFields: [String: CustomStringConvertible] { get }
}

extension CustomFieldFeedbackDescription {
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
    public var description: String {
        "\(String(describing: Self.self))(\(String(describing: feedbackFields)))"
    }
}

typealias LogTag = String

enum LogLevel: Int {
    case info
    case warn
    case error
}

struct LogMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation,
Equatable, CustomStringConvertible {
    typealias StringLiteralType = String
    
    private var value: String
    
    public init(stringLiteral value: String) {
        self.value = value
    }
    
    public var description: String {
        return self.value
    }
}

func feedbackLog(
    _ level: LogLevel, file: String = #file, line: Int = #line, _ message: LogMessage
) -> Effect<Never> {
    feedbackLog(level, type: "\(file.lastPathComponent):\(line)", value: message.description)
}

func feedbackLog<T: FeedbackDescription>(
    _ level: LogLevel, file: String = #file, line: Int = #line, _ value: T
) -> Effect<Never> {
    feedbackLog(level, type: "\(file.lastPathComponent):\(line)", value: String(describing: value))
}

func feedbackLog<T: CustomFieldFeedbackDescription>(
    _ level: LogLevel, file: String = #file, line: Int = #line, _ value: T
) -> Effect<Never> {
    feedbackLog(level, type: "\(file.lastPathComponent):\(line)", value: value.description)
}

func feedbackLog(_ level: LogLevel, tag: LogTag, _ message: LogMessage) -> Effect<Never> {
    feedbackLog(level, type: tag, value: message.description)
}

func feedbackLog<T: FeedbackDescription>(
    _ level: LogLevel, tag: LogTag, _ value: T
) -> Effect<Never> {
    feedbackLog(level, type: tag, value: String(describing: value))
}

func feedbackLog<T: CustomFieldFeedbackDescription>(
    _ level: LogLevel, tag: LogTag,  _ value: T
) -> Effect<Never> {
    feedbackLog(level, type: tag, value: value.description)
}

private func feedbackLog(_ level: LogLevel, type: String, value: String) -> Effect<Never> {
    .fireAndForget {
        switch level {
        case .info:
            PsiFeedbackLogger.info(withType: type, message: value)
        case .warn:
            PsiFeedbackLogger.warn(withType: type, message: value)
        case .error:
            PsiFeedbackLogger.error(withType: type, message: value)
        }
    }
}

/// Creates a string representation of `value` fit for sending in feedback.
/// - Note: Escapes double-quotes `"`, and removes "Psiphon" and "Swift" module names.
func makeFeedbackEntry<T: FeedbackDescription>(_ value: T) -> String {
    String(describing: value)
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "Psiphon.", with: "")
        .replacingOccurrences(of: "Swift.", with: "")
}

extension String {
    
    fileprivate var lastPathComponent: String {
        if let path = URL(string: self) {
            return path.lastPathComponent
        } else {
            return self
        }
    }
    
}
