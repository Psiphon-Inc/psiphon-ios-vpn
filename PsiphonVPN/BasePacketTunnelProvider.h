/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import <NetworkExtension/NEPacketTunnelProvider.h>
#import "NEBridge.h"

@class RACReplaySubject;

// BasePacketTunnelProvider Errors
FOUNDATION_EXTERN NSErrorDomain _Nonnull const BasePsiphonTunnelErrorDomain;

typedef NS_ERROR_ENUM(BasePsiphonTunnelErrorDomain, ABCPsiphonTunnelErrorCode) {
    BasePsiphonTunnelErrorStoppedBeforeConnected = 1000,
};


// Name of the file in shared container used to test if the extension has started,
// while the device is in locked state from boot.
#define BOOT_TEST_FILE_NAME @"boot_test_file"

typedef NS_ENUM(NSInteger, NEStartMethod) {
    /*! @const NEStartMethodFromContainer The Network Extension process was started by the container app. */
    NEStartMethodFromContainer,
    /*! @const NEStartMethodFromBoot The Network Extension process was started by "Connect On Demand" rules at boot time. */
    NEStartMethodFromBoot,
    /*! @const NEStartMethodOther The Network Extension process was either started by "Connect On Demand" rules, or by the user from system settings. */
    NEStartMethodOther,
};

#pragma mark - BasePacketTunnelProvider protocol

@protocol BasePacketTunnelProviderProtocol

@required
- (void)startTunnelWithErrorHandler:(void (^_Nonnull)(NSError *_Nonnull error))errorHandler;

- (void)stopTunnelWithReason:(NEProviderStopReason)reason;

- (void)restartTunnel;

- (BOOL)isNEZombie;

- (BOOL)isTunnelConnected;

@end

#pragma mark - BasePacketTunnelProvider

@interface BasePacketTunnelProvider : NEPacketTunnelProvider

@property (nonatomic, readonly) NEStartMethod NEStartMethod;

@property (nonatomic, readonly) BOOL VPNStarted;

/**
 * vpnStartedSignal is a finite signal that emits an item when the VPN is started and completes immediately.
 */
@property (nonatomic, nonnull) RACReplaySubject *vpnStartedSignal;

/**
 * Starts system VPN and sets the connection state to 'Connected'.
 * @return TRUE if starting VPN for the first time, FALSE otherwise.
 */
- (BOOL)startVPN;

- (BOOL)isDeviceLocked;

- (void)displayMessage:(NSString *_Nonnull)message;

@end
