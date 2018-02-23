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

/**
 * NSNotification name for VPN status change notifications.
 * Notification with this name might be posted many times,
 * without an actual change to the VPN status.
 */
FOUNDATION_EXPORT NSNotificationName _Nonnull const VPNManagerStatusDidChangeNotification;

/**
 * NSNotification name for VPN start failures.
 */
FOUNDATION_EXPORT NSNotificationName _Nonnull const VPNManagerVPNStartDidFailNotification;


FOUNDATION_EXPORT NSErrorDomain _Nonnull const VPNManagerErrorDomain;

/**
 * @typedef VPNManagerErrorCode
 * @abstract VPNManager error codes
 */
typedef NS_ERROR_ENUM(VPNManagerErrorDomain, VPNManagerStartErrorCode) {
    /*! @const VPNManagerStartErrorConfigLoadFailed Failed to load VPN configurations. */
    VPNManagerStartErrorConfigLoadFailed = 1,
    /*! @const VPNManagerStartErrorTooManyConfigsFounds More than expected VPN configurations found. */
    VPNManagerStartErrorTooManyConfigsFounds = 2,
    /*! @const VPNManagerStartErrorConfigSaveFailed Failed to save VPN configuration. */
    VPNManagerStartErrorConfigSaveFailed = 3,
    /*! @const VPNManagerStartErrorNEStartFailed Failed to start VPN. */
    VPNManagerStartErrorNEStartFailed = 4,
};

#define VPNQueryErrorUserInfoQueryKey @"query"

FOUNDATION_EXPORT NSErrorDomain _Nonnull const VPNQueryErrorDomain;

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
 * @attention VPNManager is not thread-safe.
 */
@interface VPNManager : NSObject

// TODO: remove UI flags and elements from VPNManager
@property (nonatomic) BOOL startStopButtonPressed;

+ (instancetype _Nullable)sharedInstance;

/**
 * Starts the Network Extension process and also the tunnel.
 * VPN will not start until startVPN is called.
 *
 * @details To listen for errors starting Network Extension, interested
 *          parties should observe kVPNStartFailure NSNotification.
 */
- (void)startTunnel;

/**
 * Signals the network extension to start the VPN.
 * startTunnel should be called before calling startVPN.
 */
- (void)startVPN;

/**
 * Restarts the the network extension if already active.
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
 * Whether or not VPN configuration onDemand is enabled or not.
 * @return TRUE if enabled, FALSE otherwise.
 */
- (BOOL)isOnDemandEnabled;

/**
 * Updates and saves VPN configuration Connect On Demand.
 * @param onDemandEnabled Toggle VPN configuration Connect On Demand capability.
 * @param completionHandler Block called after operation completes. error is set to nil if operation finished successfully.
 */
- (void)updateVPNConfigurationOnDemandSetting:(BOOL)onDemandEnabled completionHandler:(void (^_Nonnull)(NSError * _Nullable error))completionHandler;

#pragma mark - Extension query methods

/**
 * Queries the Network Extension whether Psiphon tunnel is in connected state or not.
 * @param completionHandler Called with tunnelIsConnected set to TRUE if Psiphon tunnel is connected, FALSE otherwise.
 */
- (void)queryNEIsTunnelConnected:(void (^ _Nonnull)(BOOL tunnelIsConnected))completionHandler;

@end
