/*
 * Copyright (c) 2017, Psiphon Inc.
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

#import "PacketTunnelUtils.h"


@implementation PacketTunnelUtils

/**
 * @brief returns human-readable text for NEProviderStopReason enums.
 * @details NEProviderStopReasonUserLogout and NEProviderStopReasonUserSwitch are available only in macOS.
 */
+ (NSString *)textStopReason:(NEProviderStopReason)stopReason {
    switch (stopReason) {
        case NEProviderStopReasonNone: return @"no specific reason";
        case NEProviderStopReasonUserInitiated: return @"user initiated";
        case NEProviderStopReasonProviderFailed: return @"provider failed to function correctly";
        case NEProviderStopReasonNoNetworkAvailable: return @"no network connectivity is currently available";
        case NEProviderStopReasonUnrecoverableNetworkChange: return @"device network connectivity changed";
        case NEProviderStopReasonProviderDisabled: return @"provider was disabled";
        case NEProviderStopReasonAuthenticationCanceled: return @"authentication process was cancelled";
        case NEProviderStopReasonConfigurationFailed: return @"the configuration is invalid";
        case NEProviderStopReasonIdleTimeout: return @"the session timed out";
        case NEProviderStopReasonConfigurationDisabled: return @"the configuration was disabled";
        case NEProviderStopReasonConfigurationRemoved: return @"the configuration was removed";
        case NEProviderStopReasonSuperceded: return @"the configuration was superceded by a higher-priority configuration";
        case NEProviderStopReasonUserLogout: return @"user logged out";
        case NEProviderStopReasonUserSwitch: return @"current console user changed";
        case NEProviderStopReasonConnectionFailed: return @"the connection failed";
    }

    return [NSString stringWithFormat:@"unknown stop reason (%ld)", (long)stopReason];
}

@end
