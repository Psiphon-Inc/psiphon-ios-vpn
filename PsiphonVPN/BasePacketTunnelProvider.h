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

// Notes on file protection:
// iOS has different file protection mechanisms to protect user's data. While this is important for protecting
// user's data, it is not needed (and offers no benefits) for application data.
//
// When files are created, iOS >7, defaults to protection level NSFileProtectionCompleteUntilFirstUserAuthentication.
// This affects files created and used by tunnel-core and the extension, preventing them to function if the
// process is started at boot but before the user has unlocked their device.
//
// To mitigate this situation, for the very first the extension runs, all folders and files required by the extension
// and tunnel-core are set to protection level NSFileProtectionNone. With the exception of the app subscription receipt
// file, which the process doesn't have rights to modify it's protection level.
// Therefore, checking subscription receipt is deferred indefinitely until the device is unlocked, and the process is
// able to open and read the file. (method isStartBootTestFileLocked performs the test that checks if the device
// has been unlocked or not.)

@class RACReplaySubject;

// BasePacketTunnelProvider Errors
FOUNDATION_EXTERN NSErrorDomain _Nonnull const BasePsiphonTunnelErrorDomain;

typedef NS_ERROR_ENUM(BasePsiphonTunnelErrorDomain, ABCPsiphonTunnelErrorCode) {
    BasePsiphonTunnelErrorStoppedBeforeConnected = 1000,
};


// Name of the file in shared container used to test if the extension has started,
// while the device is in locked state from boot.
#define BOOT_TEST_FILE_NAME @"boot_test_file"

typedef NS_ENUM(NSInteger, ExtensionStartMethodEnum) {
    /*! @const ExtensionStartMethodFromContainer The Network Extension process was started by the container app. */
    ExtensionStartMethodFromContainer,
    /*! @const ExtensionStartMethodFromBoot The Network Extension process was started by "Connect On Demand" rules at boot time. */
    ExtensionStartMethodFromBoot,
    /*! @const ExtensionStartMethodOther The Network Extension process was either started by "Connect On Demand" rules, or by the user from system settings. */
    ExtensionStartMethodOther,
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

@property (nonatomic, readonly) ExtensionStartMethodEnum extensionStartMethod;

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
