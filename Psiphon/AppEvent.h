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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TunnelState) {
    TunnelStateTunneled = 1,
    TunnelStateUntunneled,
    TunnelStateNeither
};

typedef NS_ENUM(NSInteger, SourceEvent) {
    SourceEventStarted = 101,
    SourceEventAppForegrounded = 102,
    SourceEventSubscription = 103,
    SourceEventTunneled = 104,
    SourceEventReachability = 105
};

@interface AppEvent : NSObject

// AppEvent source
@property (nonatomic, readwrite) SourceEvent source;

// AppEvent states
@property (nonatomic, readwrite) BOOL networkIsReachable;
@property (nonatomic, readwrite) BOOL subscriptionIsActive;
@property (nonatomic, readwrite) TunnelState tunnelState;

@end

NS_ASSUME_NONNULL_END
