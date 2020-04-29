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

extension AppState: FeedbackDescription {}

extension AdLoadStatus: CustomStringFeedbackDescription {
    
    public var description: String {
        switch self {
        case .none: return "none"
        case .inProgress: return "inProgress"
        case .done: return "done"
        case .error: return "error"
        @unknown default: return "unknown(\(self.rawValue)"
        }
    }
    
}

extension TunnelProviderVPNStatus: CustomStringFeedbackDescription {
    
    public var description: String {
        switch self {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown(\(self.rawValue)"
        }
    }
    
}

extension TunnelProviderSyncReason: CustomStringFeedbackDescription {
    
    public var description: String {
        switch self {
        case .appLaunched:
            return "appLaunched"
        case .appEnteredForeground:
            return "appEnteredForeground"
        case .providerNotificationPsiphonTunnelConnected:
            return "providerNotificationPsiphonTunnelConnected"
        }
    }
    
}

extension SignedAuthorization: CustomFieldFeedbackDescription {
    
    var feedbackFields: [String : CustomStringConvertible] {
        ["ID": authorization.id,
         "Expires": authorization.expires,
         "AccessType": authorization.accessType.rawValue]
    }
    
}

extension ErrorEvent: FeedbackDescription {}

extension PsiCashAmount: CustomStringFeedbackDescription {
    
    public var description: String {
        "PsiCash(inPsi %.2f: \(String(format: "%.2f", self.inPsi)))"
    }
    
}

extension UserDefaultsConfig: CustomFieldFeedbackDescription {
    
    var feedbackFields: [String : CustomStringConvertible] {
        ["expectedPsiCashReward": self.expectedPsiCashReward]
    }
    
}

extension RetriableTunneledHttpRequest.RequestResult.RetryCondition: FeedbackDescription {}
