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

public struct VPNHardCodedValues {
    
    /// Time interval during which a response to the message sent to the tunnel provider is expected.
    /// After which the send message Effect should timeout.
    public static let providerMessageSendTimeout: TimeInterval = 1.0  // 1 second
    
    /// Time interval to wait for VPN status and tunnel intent mismatch to be resolved
    /// before an alert is shown to the user.
    public static let vpnStatusAndTunnelIntentMismatchAlertDelay: TimeInterval = 5.0  // 5 seconds
    
}

public struct SubscriptionHardCodedValues {
    /// Timer leeway.
    public static let leeway: DispatchTimeInterval = .seconds(10)
    
    /// Minimum time left off of a subscription to still be considered active.
    public static let subscriptionUIMinTime: TimeInterval = 5.0  // 5 seconds
    
    /// Diff tolerance between timer's expired value and the subscription expiry value.
    /// Current value is 1 second.
    public static let subscriptionTimerDiffTolerance: TimeInterval = 1.0
    
}

public struct PurchaseVerifierURLs {
    
    public static let verifierServer = "https://subscription.psiphon3.com"
    
    public static let debugVerifierServer = "https://dev-subscription.psiphon3.com"
    
    public static let subscriptionVerify = URL(string:"\(Self.verifierServer)/v2/appstore/subscription")!
  
    public static let devSubscriptionVerify = URL(string:
        "\(Self.debugVerifierServer)/v2/appstore/subscription")!
    
    public static let psiCashVerify = URL(string: "\(Self.verifierServer)/v2/appstore/psicash")!

    public static let devPsiCashVerify = URL(string: "\(Self.debugVerifierServer)/v2/appstore/psicash")!
}

public struct UrlRequestParameters {
    
    public static let cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    
    public static let timeoutInterval: TimeInterval = 60.0
    
}
