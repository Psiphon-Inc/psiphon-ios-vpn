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

#import <Foundation/Foundation.h>

// NSNotification name for VPN status change notifications.
#define kVPNStatusChangeNotificationName "VPNStatusChange"

static NSString *const VPNManagerErrorDomain = @"VPNManagerErrorDomain";

/**
 * @typedef VPNManagerErrorCode
 * @abstract VPNManager error codes
 */
typedef NS_ERROR_ENUM(VPNManagerErrorDomain, VPNManagerStartErrorCode) {
    VPNManagerStartErrorLoadConfigsFailed = 1,
    VPNManagerStartErrorTooManyConfigsFounds = 2,
    VPNManagerStartErrorUserDeniedConfigInstall = 3,
    VPNManagerStartErrorNEStartFailed = 4,
};

#define VPNQueryErrorUserInfoQueryKey @"query"

static NSString *const VPNQueryErrorDomain = @"VPNQueryErrorDomain";
/**
 * @typedef VPNQueryErrorCode
 * @abstract VPN query error codes
 */
typedef NS_ERROR_ENUM(VPNQueryErrorDomain, VPNQueryErrorCode) {
    VPNQueryErrorSendFailed = 1,
    VPNQueryErrorNilResponse = 2,
};

/**
 * @typedef VPNStatus
 * @abstract VPN status codes
 *
 * VPNManager status is a superset of NEVPNConnection status codes.
 */
typedef NS_ENUM(NSInteger, VPNStatus) {
    /*! @const VPNStatusInvalid The VPN is not configured or unexpected vpn state. */
    VPNStatusInvalid = 0,
    /*! @const VPNStatusDisconnected No network extension process is running (When restarting VPNManager status will be VPNStatusRestarting). */
    VPNStatusDisconnected = 1,
    /*! @const VPNStatusConnecting Network extension process is running, and the tunnel has started (tunnel could be in connecting or connected state). */
    VPNStatusConnecting = 2,
    /*! @const VPNStatusConnected Network extension process is running and the tunnel is connected. */
    VPNStatusConnected = 3,
    /*! @const VPNStatusReasserting Network extension process is running, and the tunnel is reconnecting or has already connected. */
    VPNStatusReasserting = 4,
    /*! @const VPNStatusDisconnecting The tunnel and the network extension process are being stopped. */
    VPNStatusDisconnecting = 5,
    /*! @const VPNStatusRestarting Stopping previous network extension process, and starting a new one. */
    VPNStatusRestarting = 6,
};

/**
 * @interface VPNManager
 * @discussion The VPNManager class is the single point of interaction with the Network Extension.
 *
 */
@interface VPNManager : NSObject

@property (nonatomic) BOOL startStopButtonPressed;

+ (instancetype _Nullable)sharedInstance;

/**
 * Starts the network extension process and also the tunnel.
 * VPN will not start until startVPN is called.
 * @param completionHandler If no errors occurred, then error is set to nil.
 *        Error code is set to one of VPNManagerError* errors.
 */
- (void)startTunnelWithCompletionHandler:(nullable void (^)(NSError * _Nullable error))completionHandler;

/**
 * Signals the network extension to start the VPN.
 * startTunnel should be called before calling startVPN.
 */
- (void)startVPN;

/**
 * Stops the currently running network extension.
 * Note: If no network extension process is running nothing happens.
 */
- (void)restartVPNIfActive;

/**
 * Stops the tunnel and stops the network extension process.
 */
- (void)stopVPN;

/**
 * @return VPNManager status reflect NEVPNStatus of NEVPNManager
 * with the addition of a VPNStatusRestarting status.
 */
- (VPNStatus)getVPNStatus;

/**
 * @return TRUE if the VPN is in the Connecting, Connected or Reasserting state.
 */
- (BOOL)isVPNActive;

/**
 * @return TRUE if the VPN is in the Connected state.
 */
- (BOOL)isVPNConnected;

/**
 * Queries the Network Extension whether Psiphon tunnel is in connected state or not.
 * @param completionHandler Called with tunnelIsConnected set to TRUE if Psiphon tunnel is connected, FALSE otherwise.
 */
- (void)queryNEIsTunnelConnected:(void (^ _Nonnull)(BOOL tunnelIsConnected))completionHandler;

@end
