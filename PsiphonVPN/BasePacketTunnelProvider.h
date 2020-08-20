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
#import <PsiphonTunnel/PsiphonTunnel.h>
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

NS_ASSUME_NONNULL_BEGIN

@class RACReplaySubject;
@class PsiphonDataSharedDB;

// BasePacketTunnelProvider Errors
FOUNDATION_EXTERN NSErrorDomain const BasePsiphonTunnelErrorDomain;

typedef NS_ERROR_ENUM(BasePsiphonTunnelErrorDomain, ABCPsiphonTunnelErrorCode) {
    BasePsiphonTunnelErrorStoppedBeforeConnected = 1000,
};

// Name of the file in shared container used to test if the extension has started,
// while the device is in locked state from boot.
#define BOOT_TEST_FILE_NAME @"boot_test_file"

typedef NS_ENUM(NSInteger, ExtensionStartMethodEnum) {
    /*! @const ExtensionStartMethodFromContainer The Network Extension process was started by the container app. */
    ExtensionStartMethodFromContainer = 1,
    /*! @const ExtensionStartMethodFromBoot The Network Extension process was started by "Connect On Demand" rules
        at boot time. */
    ExtensionStartMethodFromBoot,
    /*! @const ExtensionStartMethodFromCrash The extension has been started due to Connect On Demand rules or
        by the user from system Settings, but the extension had previously crashed. */
    ExtensionStartMethodFromCrash,
    /*! @const ExtensionStartMethodOther The Network Extension process was either started by "Connect On Demand" rules,
        or by the user from system settings. */
    ExtensionStartMethodOther,
};

#pragma mark - BasePacketTunnelProvider protocol

@protocol BasePacketTunnelProviderProtocol

@required
- (void)startTunnelWithOptions:(NSDictionary<NSString *, NSObject *> *_Nullable)options
                  errorHandler:(void (^)(NSError *error))errorHandler;

- (void)stopTunnelWithReason:(NEProviderStopReason)reason;

- (NSNumber *)isNEZombie;

- (NSNumber *)isTunnelConnected;

- (NSNumber *)isNetworkReachable;

@end

#pragma mark - BasePacketTunnelProvider

@interface BasePacketTunnelProvider : NEPacketTunnelProvider

@property (nonatomic, readonly) ExtensionStartMethodEnum extensionStartMethod;

@property (nonatomic, readonly) BOOL VPNStarted;

@property (nonatomic, readonly) PsiphonDataSharedDB *sharedDB;

/**
 * Starts system VPN and sets the connection state to 'Connected'.
 * @return TRUE if starting VPN for the first time, FALSE otherwise.
 */
- (BOOL)startVPN;

/**
 * Exits the extension process gracefully by resetting internal flags and shutting down the tunnel.
 * Once called the tunnel is given a maximum of 5 seconds to shutdown, after which exit is called.
 *
 * @note This method should always be preferred over `abort()` and `exit()` syscalls.
 */
- (void)exitGracefully;

- (BOOL)isDeviceLocked;

- (NSString *)extensionStartMethodTextDescription;

@end

NS_ASSUME_NONNULL_END
