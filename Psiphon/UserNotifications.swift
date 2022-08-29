/*
 * Copyright (c) 2022, Psiphon Inc.
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

// UNUserNotification notifications that are requested by the NE.
enum LocalNotificationIdentifier {
    case OpenContainer
    case CorruptSettings
    case SubscriptionExpired
    case RegionUnavailable
    case UpstreamProxyError
    case DisallowedTraffic
    case MustStartVPNFromApp
    case PurchaseRequired
}

extension LocalNotificationIdentifier {
    
    /// Whether or not a presented notification should be dismissed on app foreground.
    var dismissDeliveredNotifOnForeground: Bool {
        switch self {
        case .CorruptSettings, .UpstreamProxyError:
            return false
        case .OpenContainer,
                .SubscriptionExpired,
                .RegionUnavailable,
                .DisallowedTraffic,
                .MustStartVPNFromApp,
                .PurchaseRequired:
            return true
        }
    }
    
    /// Whether or not to silence the notification when the app is running in the foreground.
    var silenceNotificationIfOnForeground: Bool {
        switch self {
        case .OpenContainer:
            return true
        case .CorruptSettings,
                .SubscriptionExpired,
                .RegionUnavailable,
                .UpstreamProxyError,
                .DisallowedTraffic,
                .MustStartVPNFromApp,
                .PurchaseRequired:
            return false
        }
    }
    
}

extension LocalNotificationIdentifier: RawRepresentable {
    
    init?(rawValue: String) {
        switch rawValue {
        case NotificationIdOpenContainer:
            self = .OpenContainer
        case NotificationIdCorruptSettings:
            self = .CorruptSettings
        case NotificationIdSubscriptionExpired:
            self = .SubscriptionExpired
        case NotificationIdRegionUnavailable:
            self = .RegionUnavailable
        case NotificationIdUpstreamProxyError:
            self = .UpstreamProxyError
        case NotificationIdDisallowedTraffic:
            self =  .DisallowedTraffic
        case NotificationIdMustStartVPNFromApp:
            self =  .MustStartVPNFromApp
        case NotificationIdPurchaseRequired:
            self = .PurchaseRequired
        default:
            return nil
        }
    }
    
    var rawValue: String {
        switch self {
        case .OpenContainer:
            return NotificationIdOpenContainer
        case .CorruptSettings:
            return NotificationIdCorruptSettings
        case .SubscriptionExpired:
            return NotificationIdSubscriptionExpired
        case .RegionUnavailable:
            return NotificationIdRegionUnavailable
        case .UpstreamProxyError:
            return NotificationIdUpstreamProxyError
        case .DisallowedTraffic:
            return NotificationIdDisallowedTraffic
        case .MustStartVPNFromApp:
            return NotificationIdMustStartVPNFromApp
        case .PurchaseRequired:
            return NotificationIdPurchaseRequired
        }
    }
    
}

