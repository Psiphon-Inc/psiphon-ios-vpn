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

final class PsiphonRotatingFileFeedbackLogHandler: FeedbackLogHandler {
    
    func fatalError(type: String, message: String) {
        PsiFeedbackLogger.fatalError(withType: type, message: message)
        Swift.fatalError(type)
    }
    
    func feedbackLog(level: NonFatalLogLevel, type: String, message: String) {
        switch level {
        case .info:
            PsiFeedbackLogger.info(withType: type, message: message)
        case .warn:
            PsiFeedbackLogger.warn(withType: type, message: message)
        case .error:
            PsiFeedbackLogger.error(withType: type, message: message)
        }
    }

    func feedbackLogNotice(type: String, message: String, timestamp: String) {
        PsiFeedbackLogger.logNotice(withType: type, message: message, timestamp: timestamp)
    }

}
