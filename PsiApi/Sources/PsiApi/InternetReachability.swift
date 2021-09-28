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
import Utilities
import ReactiveSwift

@objc public enum ReachabilityStatus: Int, CustomStringFeedbackDescription {

    case notReachable
    case viaWiFi
    case viaWWAN

    public var description: String {
        switch self {
        case .notReachable:
            return "ReachabilityStatus.notReachable"
        case .viaWiFi:
            return "ReachabilityStatus.viaWiFi"
        case .viaWWAN:
            return "ReachabilityStatus.viaWWAN"
        }
    }

}

/// Represents reachability status flags coded into a string.
public struct ReachabilityCodedStatus: TypedIdentifier {
    public var rawValue: String { value }
    
    private let value: String
    
    public init?(rawValue: String) {
        self.value = rawValue
    }
}

public enum ReachabilityAction {
    case reachabilityStatus(ReachabilityStatus, ReachabilityCodedStatus)
}

public struct ReachabilityState: Equatable {
    public var networkStatus: ReachabilityStatus
    public var codedStatus: ReachabilityCodedStatus
    
    public init(networkStatus: ReachabilityStatus = .notReachable,
                codedStatus: ReachabilityCodedStatus? = nil) {
        self.networkStatus = networkStatus
        self.codedStatus = codedStatus ?? ReachabilityCodedStatus(rawValue: "")!
    }
}

public let internetReachabilityReducer = Reducer<ReachabilityState, ReachabilityAction, ()> {
    state, action, environment in
    
    switch action {
    case let .reachabilityStatus(updatedStatus, updatedCodedStatus):
        state.networkStatus = updatedStatus
        state.codedStatus = updatedCodedStatus
        return []
    }
    
}

public protocol InternetReachability {
    
    func currentStatus() -> ReachabilityStatus
    
    func currentReachabilityFlags() -> ReachabilityCodedStatus
    
}

extension InternetReachability {
    
    public var isCurrentlyReachable: Bool {
        let status = self.currentStatus()
        switch status {
        case .notReachable: return false
        case .viaWiFi: return true
        case .viaWWAN: return true
        }
    }
    
}
