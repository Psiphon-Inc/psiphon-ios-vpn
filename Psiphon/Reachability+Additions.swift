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

extension ReachabilityStatus {
    
    init(objcNetworkStatus: NetworkStatus) {
        switch objcNetworkStatus {
        case NotReachable:
            self = .notReachable
        case ReachableViaWiFi:
            self = .viaWiFi
        case ReachableViaWWAN:
            self = .viaWWAN
        default:
            fatalError("Unknown reachability status '\(objcNetworkStatus)'")
        }
    }
}

extension Reachability: InternetReachability {
    
    func currentStatus() -> ReachabilityStatus {
        ReachabilityStatus(objcNetworkStatus: self.currentReachabilityStatus())
    }
    
    func currentReachabilityFlags() -> ReachabilityCodedStatus {
        ReachabilityCodedStatus(stringLiteral: self.currentReachabilityFlagsToString())
    }
    
}

final class InternetReachabilityDelegate: StoreDelegate<ReachabilityAction> {
    
    private let reachability: Reachability
    
    init(reachability: Reachability, store: Store<Unit, ReachabilityAction>) {
        self.reachability = reachability
        super.init(store: store)
        
        self.reachability.startNotifier()
        NotificationCenter.default.addObserver(self, selector: #selector(statusDidChange),
                                               name: NSNotification.Name.reachabilityChanged,
                                               object: self.reachability)
        
        // Sends current state before notifications for status change kick in.
        statusDidChange()
    }
    
    @objc private func statusDidChange() {
        let networkStatus = self.reachability.currentReachabilityStatus()
        let codedStatus = self.reachability.currentReachabilityFlagsToString()!
        
        storeSend(
            .reachabilityStatus(
                ReachabilityStatus(objcNetworkStatus: networkStatus),
                ReachabilityCodedStatus(stringLiteral: codedStatus)
            )
        )
    }
    
    deinit {
        self.reachability.stopNotifier()
        NotificationCenter.default.removeObserver(self,
                                                  name: NSNotification.Name.reachabilityChanged,
                                                  object: self.reachability)
    }
    
}

