/*
 * Copyright (c) 2021, Psiphon Inc.
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
import PsiphonClientCommonLibrary

// Example diagnostic log format:
// {"data":{"message":"shutdown operate tunnel"},"noticeType":"Info","showUser":false,"timestamp":"2006-01-02T15:04:05.999-07:00"}
fileprivate struct FeedbackLog: Equatable {
    let data: String
    let noticeType: String
    let showUser: Bool
    let timestamp: Date
}

/// Represents any error encountered while parsing feedback logs.
struct FeedbackLogParseError: Error {
    let message: String
    let timestamp: Date
}

/// Parses new-line `\n` separated diagnostic lines.
func parseLogs(
    _ data: String, getCurrentTime: () -> Date
) -> ([DiagnosticEntry], [FeedbackLogParseError]) {
    
    var entries = [DiagnosticEntry]()
    var parseErrors = [FeedbackLogParseError]()
    
    for logLine in data.split(separator: "\n") {
        
        guard !logLine.isEmpty else  {
            continue
        }
        
        guard let data = logLine.data(using: .utf8) else {
            fatalError()
        }
        
        do {
            
            let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            guard let dict = dict else {
                parseErrors.append(
                    FeedbackLogParseError(
                        message: "expected a dictionary: '\(data)'",
                        timestamp: getCurrentTime()))
                continue
            }
            
            guard let noticeType = dict["noticeType"] as? String else {
                parseErrors.append(
                    FeedbackLogParseError(
                        message: "noticeType not found: '\(logLine)'",
                        timestamp: getCurrentTime()))
                continue
            }
            
            guard let noticeDataDict = dict["data"] as? [String: Any] else {
                parseErrors.append(
                    FeedbackLogParseError(
                        message: "expected a dictionary: '\(logLine)'",
                        timestamp: getCurrentTime()))
                continue
            }
            
            let noticeData = try JSONSerialization.data(withJSONObject: noticeDataDict, options: [])
            
            guard let noticeData_str = String(data: noticeData, encoding: .utf8) else {
                fatalError()
            }
            
            guard let timestamp = Date.parse(rfc3339Date: dict["timestamp"] as! String) else {
                parseErrors.append(
                    FeedbackLogParseError(
                        message: "failed to parse timestamp: '\(logLine)'",
                        timestamp: getCurrentTime()))
                continue
            }
            
            let entry = DiagnosticEntry(
                "\(noticeType): \(noticeData_str)",
                andTimestamp: timestamp
            )!
            
            entries.append(entry)
            
        } catch {
            parseErrors.append(
                FeedbackLogParseError(
                    message: "failed to parse '\(logLine): \(error)'",
                    timestamp: getCurrentTime()))
            continue
        }
        
    }
    
    return (entries, parseErrors)
    
}


/// Represents the different sources/processes that write feedback logs.
/// These include the host app (container), the logs written by the Network Extension,
/// and logs written by tunnel-core running inside the Network Extension
enum FeedbackLogSource: String, CaseIterable {
    /// Host application (container)
    case hostApp
    /// Logs produced in the Network Extension outside of the tunnel-core.
    case networkExtension
    /// Logs produced in the Network Extension by tunnel-core.
    case tunnelCore
}

extension FeedbackLogSource {
    
    func getLogNoticesPath(_ dataRootDirectory: URL?) -> String? {
        switch self {
        case .hostApp:
            return PsiFeedbackLogger.containerRotatingLogNoticesPath
        case .networkExtension:
            return PsiFeedbackLogger.extensionRotatingLogNoticesPath
        case .tunnelCore:
            if let dataRootDirectory = dataRootDirectory {
                return PsiphonTunnel.noticesFilePath(dataRootDirectory)?.path
            } else {
                return nil
            }
        }
    }
    
    func getOlderLogNoticesPath(_ dataRootDirectory: URL?) -> String? {
        switch self {
        case .hostApp:
            return PsiFeedbackLogger.containerRotatingOlderLogNoticesPath
        case .networkExtension:
            return PsiFeedbackLogger.extensionRotatingOlderLogNoticesPath
        case .tunnelCore:
            if let dataRootDirectory = dataRootDirectory {
                return PsiphonTunnel.olderNoticesFilePath(dataRootDirectory)?.path
            } else {
                return nil
            }
        }
    }
    
}

/// Parses selected diagnostic log files according to `logTypes`.
/// The returned `DiagnosticEntry` array is sorted by timestamp in ascending order.
func getFeedbackLogs(
    for logTypes: Set<FeedbackLogSource>,
    dataRootDirectory: URL?,
    getCurrentTime: () -> Date
) -> ([DiagnosticEntry], [FeedbackLogParseError]) {
    
    var entries = [DiagnosticEntry]()
    var parseErrors = [FeedbackLogParseError]()
    
    var logFilePaths = Set<String>()
    
    for logType in logTypes {
        logFilePaths.insert(logType.getLogNoticesPath(dataRootDirectory) ?? "")
        logFilePaths.insert(logType.getOlderLogNoticesPath(dataRootDirectory) ?? "")
    }
    
    for logFilePath in logFilePaths {
        
        if let fileContent = FileUtils.tryReadingFile(logFilePath) {
            let result = parseLogs(fileContent, getCurrentTime: getCurrentTime)
            entries.append(contentsOf: result.0)
            parseErrors.append(contentsOf: result.1)
        }
        
    }
    
    // Sorts the entries by timestamp in ascending order.
    entries.sort {
        $0.timestamp < $1.timestamp
    }
    
    return (entries, parseErrors)
    
}
