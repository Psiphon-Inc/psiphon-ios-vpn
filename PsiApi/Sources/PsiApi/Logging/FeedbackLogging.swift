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

public typealias LogTag = String

public enum NonFatalLogLevel: String, Codable {
    case info
    case warn
    case error
}

enum LogLevel: Equatable {
    case fatal
    case nonFatal(NonFatalLogLevel)
}

public protocol FeedbackLogHandler {
    
    func fatalError(type: String, message: String)
    
    func feedbackLog(level: NonFatalLogLevel, type: String, message: String)
    
}

public struct StdoutFeedbackLogger: FeedbackLogHandler {
    
    public func fatalError(type: String, message: String) {
        print("[FatalError] type: '\(type)' message: '\(message)'")
    }
    
    public func feedbackLog(level: NonFatalLogLevel, type: String, message: String) {
        print("[\(String(describing: level))] type: '\(type)' message: '\(message)'")
    }
    
}

final class ArrayFeedbackLogHandler: FeedbackLogHandler {
    
    struct Log: Equatable {
        let level: LogLevel
        let type: String
        let message: String
    }
    
    var logs = [Log]()
    
    func fatalError(type: String, message: String) {
        logs.append(Log(level: .fatal, type: type, message: message))
    }
    
    func feedbackLog(level: NonFatalLogLevel, type: String, message: String) {
        logs.append(Log(level: .nonFatal(level), type: type, message: message))
    }
    
}

public struct LogMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation,
Equatable, CustomStringConvertible, CustomStringFeedbackDescription, FeedbackDescription {
    public typealias StringLiteralType = String
    
    private var value: String
    
    public init(stringLiteral value: String) {
        self.value = value
    }
    
    public var description: String {
        return self.value
    }
}

public struct FeedbackLogger {
    
    let handler: FeedbackLogHandler
    
    public init(_ handler: FeedbackLogHandler) {
        self.handler = handler
    }
    
    public func fatalError(
        _ message: LogMessage, file: String = #file, line: UInt = #line
    ) {
        let tag = "\(file.lastPathComponent):\(line)"
        handler.fatalError(type: tag, message: message.description)
    }

    public func precondition(
        _ condition: @autoclosure () -> Bool, _ message: LogMessage,
        file: String = #file, line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
            return
        }
    }

    public func preconditionFailure(
        _ message: LogMessage, file: String = #file, line: UInt = #line
    ) {
        fatalError(message, file: file, line: line)
    }

    public func log(
        _ level: NonFatalLogLevel, file: String = #file, line: Int = #line, _ message: LogMessage
    ) -> Effect<Never> {
        log(level, type: "\(file.lastPathComponent):\(line)", value: message.description)
    }

    public func log<T: FeedbackDescription>(
        _ level: NonFatalLogLevel, file: String = #file, line: Int = #line, _ value: T
    ) -> Effect<Never> {
        log(level, type: "\(file.lastPathComponent):\(line)", value: String(describing: value))
    }

    public func log<T: CustomFieldFeedbackDescription>(
        _ level: NonFatalLogLevel, file: String = #file, line: Int = #line, _ value: T
    ) -> Effect<Never> {
        log(level, type: "\(file.lastPathComponent):\(line)", value: value.description)
    }

    public func log(_ level: NonFatalLogLevel, tag: LogTag, _ message: LogMessage) -> Effect<Never> {
        log(level, type: tag, value: message.description)
    }

    public func log<T: FeedbackDescription>(
        _ level: NonFatalLogLevel, tag: LogTag, _ value: T
    ) -> Effect<Never> {
        log(level, type: tag, value: String(describing: value))
    }

    public func log<T: CustomFieldFeedbackDescription>(
        _ level: NonFatalLogLevel, tag: LogTag,  _ value: T
    ) -> Effect<Never> {
        log(level, type: tag, value: value.description)
    }

    private func log(_ level: NonFatalLogLevel, type: String, value: String) -> Effect<Never> {
        .fireAndForget {
            self.handler.feedbackLog(level: level, type: type, message: value)
        }
    }

    public func immediate(
        _ level: NonFatalLogLevel, _ value: LogMessage, file: String = #file, line: UInt = #line
    ) {
        let tag = "\(file.lastPathComponent):\(line)"
        let message = makeFeedbackEntry(value)
        handler.feedbackLog(level: level, type: tag, message: message)
    }
    
}

/// Creates a string representation of `value` fit for sending in feedback.
/// - Note: Escapes double-quotes `"`, and removes "Psiphon" and "Swift" module names.
public func makeFeedbackEntry<T: FeedbackDescription>(_ value: T) -> String {
    normalizeFeedbackDescriptionTypes(String(describing: value))
}

/// Creates a string representation of `value` fit for sending in feedback.
/// - Note: Escapes double-quotes `"`, and removes "Psiphon" and "Swift" module names.
func makeFeedbackEntry<T: CustomFieldFeedbackDescription>(_ value: T) -> String {
    normalizeFeedbackDescriptionTypes(value.description)
}

fileprivate func normalizeFeedbackDescriptionTypes(_ value: String) -> String {
    value.replacingOccurrences(of: "\"", with: "\\\"")
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

// MARK: Default FeedbackDescription conformances

extension Optional: FeedbackDescription {}
