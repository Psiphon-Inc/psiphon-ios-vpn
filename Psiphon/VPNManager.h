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

#define kVPNManagerErrorDomain @"VPNManagerErrorDomain"
typedef NS_ENUM(NSInteger, VPNManagerErrorCode) {
    VPNManagerErrorLoadConfigsFailed = 1,
    VPNManagerErrorTooManyConfigsFounds = 2,
    VPNManagerErrorUserDeniedConfigInstall = 3,
    VPNManagerErrorNEStartFailed = 4,
};

typedef NS_ENUM(NSInteger, VPNStatus) {
    VPNStatusInvalid = 0,
    /*! @const VPNStatusDisconnected No network extension process is running (When restarting VPNManager status will be VPNStatusRestarting). */
    VPNStatusDisconnected = 1,
    /*! @const VPNStatusConnecting network extension process is running, and the tunnel has started (tunnel could be in connecting or connected state). */
    VPNStatusConnecting = 2,
    /*!VPNStatusConnected network extension process is running and the tunnel is connected. */
    VPNStatusConnected = 3,
    /*!VPNStatusReasserting network extension process is running, and the tunnel is reconnecting or has already connected. */
    VPNStatusReasserting = 4,
    /*!VPNStatusDisconnecting tunnel and the network extension process are being stopped.*/
    VPNStatusDisconnecting = 5,
    /*! @const VPNStatusRestarting Stopping previous network extension process, and starting a new one. */
    VPNStatusRestarting = 6,
};

@interface VPNManager : NSObject

+ (instancetype)sharedInstance;

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
- (void)restartVPN;

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
 * @return TRUE if the tunnel has connected, FALSE otherwise.
 */
- (BOOL)isTunnelConnected;

@end
