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
#import "VPNStrings.h"

@implementation VPNStrings

+ (NSString *)disallowedTrafficAlertMessage {
    return NSLocalizedStringWithDefaultValue(@"DISALLOWED_TRAFFIC_EXTENSION_ALERT", nil, [NSBundle mainBundle], @"Some Internet traffic is not supported by the free version of Psiphon. Purchase a subscription or Speed Boost to unlock the full potential of your Psiphon experience.", @"Alert dialog which is shown to the user when if unsupported Internet traffic has been requested");
}

+ (NSString *)disallowedTrafficNotificationTitle {
    return NSLocalizedStringWithDefaultValue(@"NOTIFICATION_TITLE_UPGRADE_PSIPHON", nil, [NSBundle mainBundle], @"Upgrade Psiphon", @"Title of the user notification which is shown to the user when Psiphon server detects an unsupported Internet traffic request");
}

+ (NSString *)disallowedTrafficNotificationBody {
    return NSLocalizedStringWithDefaultValue(@"NOTIFICATION_BODY_DISALLOWED_TRAFFIC_ALERT", nil, [NSBundle mainBundle], @"Apps not working? Tap here to improve your Psiphon experience!", @"Content of the user notification which is shown to the user when Psiphon server detects an unsupported Internet traffic request");
}

+ (NSString *)corruptSettingsFileAlertMessage {
    return NSLocalizedStringWithDefaultValue(@"CORRUPT_SETTINGS_MESSAGE", nil, [NSBundle mainBundle], @"Your app settings file appears to be corrupt. Try reinstalling the app to repair the file.", @"Alert dialog message informing the user that the settings file in the app is corrupt, and that they can potentially fix this issue by re-installing the app.");
}

+ (NSString *)cannotStartTunnelDueToSubscription {
    return NSLocalizedStringWithDefaultValue(@"CANNOT_START_TUNNEL_DUE_TO_SUBSCRIPTION", nil, [NSBundle mainBundle], @"You don't have an active subscription.\nSince you're not a subscriber or your subscription has expired, Psiphon can only be started from the Psiphon app.\n\nPlease open the Psiphon app to start.", @"Alert message informing user that their subscription has expired or that they're not a subscriber, therefore Psiphon can only be started from the Psiphon app. DO NOT translate 'Psiphon'.");
}

+ (NSString *)openPsiphonAppToFinishConnecting {
    return NSLocalizedStringWithDefaultValue(@"OPEN_PSIPHON_APP", nil, [NSBundle mainBundle], @"Please open Psiphon app to finish connecting.", @"Alert message informing the user they should open the app to finish connecting to the VPN. DO NOT translate 'Psiphon'.");
}

+ (NSString *)upstreamProxySettingsErrorMessage {
    return NSLocalizedStringWithDefaultValue(@"CHECK_UPSTREAM_PROXY_SETTING", nil, [NSBundle mainBundle], @"You have configured Psiphon to use an upstream proxy.\nHowever, we seem to be unable to connect to a Psiphon server through that proxy.\nPlease fix the settings and try again.", @"Main text in the 'Upstream Proxy Error' dialog box. This is shown when the user has directly altered these settings, and those settings are (probably) erroneous. DO NOT translate 'Psiphon'.");
}

+ (NSString *)subscriptionExpiredAlertMessage {
    return NSLocalizedStringWithDefaultValue(@"EXTENSION_EXPIRED_SUBSCRIPTION_ALERT", nil, [NSBundle mainBundle], @"Your Psiphon subscription has expired.\n\n Please open Psiphon app to renew your subscription.", @"");
}

@end
