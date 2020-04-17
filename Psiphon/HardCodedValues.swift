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

struct VPNHardCodedValues {
    
    /// Time interval during which a response to the messent sent to the tunnel provider is expected.
    /// After which the send message Effect should timeout.
    static let providerMessageSendTimeout: TimeInterval = 5.0  // 5 seconds
    
    /// Debounce time interval for forwarding sync state errrors.
    static let syncStateErrorDebounceInterval: TimeInterval = 5.0  // 5 seconds
    
}

struct PsiCashHardCodedValues {
    static let videoAdRewardAmount = PsiCashAmount(nanoPsi: Int64(35e9))
    static let videoAdRewardTitle = "35"
    /// Amount of time to wait for PsiCash to have an earner token for modifying .
    static let getEarnerTokenTimeout: DispatchTimeInterval = .seconds(5)
}

struct SubscriptionHardCodedValues {
    /// Timer leeway.
    static let leeway: DispatchTimeInterval = .seconds(10)

    /// Minimum time interval in seconds before the subscription expires
    /// that will trigger a forced subscription check in the network extension.
    static let notifierMinSubDuration: TimeInterval = 60.0  // 60 seconds
    
    /// Minimum time left of a subscription to still be considered active.
    static let subscriptionUIMinTime: TimeInterval = 1.0  // 1 second
    
    /// Minimum amount of time left on a subscription to do a subscription check.
    static let subscriptionCheckMinTime: TimeInterval = 60.0  // 60 seconds
    
    /// Diff tolerance between timer's expired value and the subscription expiry value.
    /// Current value is 1 second.
    static let subscriptionTimerDiffTolerance: TimeInterval = 1.0
    
    init() {
        precondition(Self.subscriptionCheckMinTime > Self.subscriptionUIMinTime)
    }
}
