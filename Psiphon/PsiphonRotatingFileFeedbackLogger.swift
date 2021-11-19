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
import PsiApi
import Utilities

final class PsiphonRotatingFileFeedbackLogHandler: FeedbackLogHandler {
    
    private var lastReportedLog: Date? = nil
    private var reportedLogSubscriber: ((Date) -> Void)? = nil
    
    func setReportedLogSubscriber(_ subscriber: @escaping (Date) -> Void) {
        guard self.reportedLogSubscriber == nil else {
            Swift.fatalError()
        }
        self.reportedLogSubscriber = subscriber
        if let lastReportedLog = lastReportedLog {
            subscriber(lastReportedLog)
        }
    }
    
    func fatalError(type: String, message: String) {
        PsiFeedbackLogger.fatalError(withType: type, message: message)
        Swift.fatalError(type)
    }
    
    /// - Parameter report: If `true` then
    func feedbackLog(level: NonFatalLogLevel, report: Bool, type: String, message: String) {
        
        switch level {
        case .info:
            PsiFeedbackLogger.info(withType: type, message: message)
        case .warn:
            PsiFeedbackLogger.warn(withType: type, message: message)
        case .error:
            PsiFeedbackLogger.error(withType: type, message: message)
        }
        
        if report {
            
            // TODO: PsiFeedbackLogger creates it's own date object for this log.
            // Create only one Date object, and share.
            let logDate = Date()
            
            lastReportedLog = logDate
            
            if let subscriber = self.reportedLogSubscriber {
                subscriber(logDate)
            }
            
        }
        
    }

    func feedbackLogNotice(type: String, message: String, timestamp: String) {
        PsiFeedbackLogger.logNotice(withType: type, message: message, timestamp: timestamp)
    }

}
