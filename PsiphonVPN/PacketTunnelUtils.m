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

#import <PsiphonTunnel/PsiphonTunnel.h>
#import "PacketTunnelUtils.h"


@implementation PacketTunnelUtils

/**
 * @brief returns human-readable text for NEProviderStopReason enums.
 * @details NEProviderStopReasonUserLogout and NEProviderStopReasonUserSwitch are available only in macOS.
 */
+ (NSString *)textStopReason:(NEProviderStopReason)stopReason {
    switch (stopReason) {
        case NEProviderStopReasonNone : return @"None";
        case NEProviderStopReasonUserInitiated :return @"UserInitiated";
        case NEProviderStopReasonProviderFailed :return @"ProviderFailed";
        case NEProviderStopReasonNoNetworkAvailable :return @"NoNetworkAvailable";
        case NEProviderStopReasonUnrecoverableNetworkChange :return @"UnrecoverableNetworkChange";
        case NEProviderStopReasonProviderDisabled :return @"ProviderDisabled";
        case NEProviderStopReasonAuthenticationCanceled :return @"AuthenticationCanceled";
        case NEProviderStopReasonConfigurationFailed :return @"ConfigurationFailed";
        case NEProviderStopReasonIdleTimeout :return @"IdleTimeout";
        case NEProviderStopReasonConfigurationDisabled :return @"ConfigurationDisabled";
        case NEProviderStopReasonConfigurationRemoved :return @"ConfigurationRemoved";
        case NEProviderStopReasonSuperceded :return @"Superceded";
        case NEProviderStopReasonUserLogout :return @"UserLogout";
        case NEProviderStopReasonUserSwitch :return @"UserSwitch";
        case NEProviderStopReasonConnectionFailed :return @"ConnectionFailed";
        default: return @"Unknown";
    }
}

+ (NSString *)textPsiphonConnectionState:(PsiphonConnectionState)state {
    switch (state) {
        case PsiphonConnectionStateDisconnected:
            return @"Disconnected";
        case PsiphonConnectionStateConnecting:
            return @"Connecting";
        case PsiphonConnectionStateConnected:
            return @"Connected";
        case PsiphonConnectionStateWaitingForNetwork:
            return @"WaitingForNetwork";
        default: return @"None";
    }
}

@end
