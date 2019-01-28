/*
 * Copyright (c) 2019, Psiphon Inc.
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

#import "AppEvent.h"
#import "Logging.h"


@implementation AppEvent

// Two app events are equal only if all properties except the `source` are equal.
- (BOOL)isEqual:(AppEvent *)other {
    if (other == self)
        return TRUE;
    if (!other || ![[other class] isEqual:[self class]])
        return FALSE;
    return (self.networkIsReachable == other.networkIsReachable &&
      self.subscriptionIsActive == other.subscriptionIsActive &&
      self.tunnelState == other.tunnelState);
}

- (NSString *)debugDescription {

    NSString *sourceText;
    switch (self.source) {
        case SourceEventAppForegrounded:
            sourceText = @"SourceEventAppForegrounded";
            break;
        case SourceEventSubscription:
            sourceText = @"SourceEventSubscription";
            break;
        case SourceEventTunneled:
            sourceText = @"SourceEventTunneled";
            break;
        case SourceEventStarted:
            sourceText = @"SourceEventStarted";
            break;
        case SourceEventReachability:
            sourceText = @"SourceEventReachability";
            break;
        default: abort();
    }

    NSString *tunnelStateText;
    switch (self.tunnelState) {
        case TunnelStateTunneled:
            tunnelStateText = @"TunnelStateTunneled";
            break;
        case TunnelStateUntunneled:
            tunnelStateText = @"TunnelStateUntunneled";
            break;
        case TunnelStateNeither:
            tunnelStateText = @"TunnelStateNeither";
            break;
        default: abort();
    }

    return [NSString stringWithFormat:@"<AppEvent source=%@ networkIsReachable=%@ subscriptionIsActive=%@ "
                                      "tunnelState=%@>", sourceText, NSStringFromBOOL(self.networkIsReachable),
                                      NSStringFromBOOL(self.subscriptionIsActive), tunnelStateText];
}

@end