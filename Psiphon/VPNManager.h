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

#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#import "UserDefaults.h"

NS_ASSUME_NONNULL_BEGIN

@class RACSubject<ValueType>;
@class RACReplaySubject<ValueType>;
@class RACSignal<__covariant ValueType>;
@class RACTwoTuple<__covariant First, __covariant Second>;
@class RACUnit;

FOUNDATION_EXPORT NSErrorDomain const VPNManagerErrorDomain;

typedef NS_ERROR_ENUM(VPNManagerErrorDomain, VPNManagerConfigErrorCode) {
    /*! @const VPNManagerStartErrorConfigLoadFailed Failed to load VPN configurations. */
    VPNManagerConfigErrorLoadFailed = 100,
    /*! @const VPNManagerStartErrorTooManyConfigsFounds More than expected VPN configurations found. */
    VPNManagerConfigErrorTooManyConfigsFounds = 101,
    /*! @const VPNManagerStartErrorConfigSaveFailed Failed to save VPN configuration. */
    VPNManagerConfigErrorConfigSaveFailed = 102,
};

typedef NS_ERROR_ENUM(VPNManagerErrorDomain, VPNManagerQueryErrorCode) {

    VPNManagerQuerySendFailed = 200,

    VPNManagerQueryNilResponse = 201,
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
    /*! @const VPNStatusZombie Network extension is in the zombie state. */
    VPNStatusZombie = 7,
};

typedef NS_ENUM(NSInteger, VPNStartStatus) {
    /*! @const VPNStartStatusStart The VPN start process has started. */
    VPNStartStatusStart,
    /*! @const VPNStartStatusFinished The VPN start process has finished successfully. */
    VPNStartStatusFinished,
    /*! @const VPNStartStatusFailedUserPermissionDenied The VPN start process failed due to user denying installation of a VPN configuration. */
    VPNStartStatusFailedUserPermissionDenied,
    /*! @const VPNStartStatusFailedOther The VPN start process failed due to any reason other than user denying permission. */
    VPNStartStatusFailedOther
};

@interface VPNManager : NSObject

/**
 * vpnStartStatus replay subject emits one of VPNStartStatus enums,
 * from when startTunnel is called to when it finishes.
 *
 * @scheduler vpnStartStatus delivers its events on the main thread.
 */
@property (nonatomic, readonly) RACSignal<NSNumber *> *vpnStartStatus;

/**
 * Emits the last know VPN status (type VPNStatus).
 * This replay subject is never empty and starts with `VPNStatusInvalid`,
 * until the VPN configuration is loaded (if any).
 *
 * @note If the last tunnel status is unknown at the time of subscription (e.g. when the
 *       app is recently foregrounded), the signal will not emit anything until the tunnel status is determined.
 *
 * @attention This observable may not emit the latest VPN status when subscribed to.
 *
 * @scheduler lastTunnelStatus delivers its events on the main thread.
 */
@property (nonatomic, readonly) RACSignal<NSNumber *> *lastTunnelStatus;

/**
 * VPN status code from underlying NETunnelProviderManager.
 */
@property (nonatomic, readonly) NEVPNStatus tunnelProviderStatus;

+ (VPNManager *)sharedInstance;

/**
 * Returns text description of VPNStatus.
 */
+ (NSString *)statusText:(NSInteger)status;

/**
 * Returns text description of NEVPNStatus.
 */
+ (NSString *)statusTextSystem:(NEVPNStatus)status;

/**
 * Returned signal emits @(TRUE) if VPN configuration is already installed, @(FALSE) otherwise.
 */
- (RACSignal<NSNumber *> *)vpnConfigurationInstalled;

/**
 * Must be called whenever the application becomes active for VPNManager to update its status.
 */
- (void)checkOrFixVPNStatus;

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
 * Stops the tunnel and stops the network extension process.
 */
- (void)stopVPN;

/**
 * Restarts the the network extension if already active.
 * Note: If no network extension process is running nothing happens.
 */
- (void)restartVPNIfActive;


/**
 * Removes and installs the VPN configuration.
 */
- (void)reinstallVPNConfiguration;

/**
 * Returns TRUE if VPNStatus is in an active state.
 *
 * @details VPN state is considered active if it is one of the following: `VPNStatusConnecting`, `VPNStatusConnected`,
 *          `VPNStatusReasserting` and `VPNStatusRestarting`.
 * @param s VPN status.
 * @return TRUE if status `s` is considered active, FALSE otherwise.
 */
+ (BOOL)mapIsVPNActive:(VPNStatus)s;

/**
 * isVPNActive returns a signal that when subscribed to, queries the extension if its zombie,
 * and then checks NETunnelProviderManager connection status if the extension is not in the zombie state.
 * Returned signal emits a RACTwoTuple of (is vpn active, vpn status), and then completes.
 *
 * If no VPN configuration was previously saved, it emits `(FALSE, VPNStatusInvalid)` tuple.
 *
 * @scheduler isVPNActive delivers its events on a background thread.
 *
 */
- (RACSignal<RACTwoTuple<NSNumber *, NSNumber *> *> *)isVPNActive;

/**
 * isConnectOnDemandEnabled signal when subscribed to emits TRUE as NSNumber
 * if the VPN configuration's Connect On Demand is enabled, emits FALSE otherwise.
 *
 * @scheduler isConnectOnDemandEnabled delivers its events on a background thread.
 */
- (RACSignal<NSNumber *> *)isConnectOnDemandEnabled;

/**
 * Updates and saves VPN configuration Connect On Demand.
 *
 * The returned signal emits @(TRUE) if succeeded, @(FALSE) otherwise, and then completes.
 * All internal errors are caught, and instead FALSE is emitted.
 *
 * @param onDemandEnabled Toggle VPN configuration Connect On Demand capability.
 *
 * @scheduler setConnectOnDemandEnabled: delivers its events on a background thread.
 */
- (RACSignal<NSNumber *> *)setConnectOnDemandEnabled:(BOOL)onDemandEnabled;

/**
 * Queries the Network Extension whether it is in the zombie state.
 * @attention Returned signal emits nil if there is no active session.
 *
 * @scheduler isExtensionZombie delivers its events on a background thread.
 */
- (RACSignal<NSNumber *> *)isExtensionZombie;

/**
 * Queries the Network Extension whether Psiphon tunnel is in connected state or not.
 * @attention Returned signal emits nil if there is no active session.
 *
 * @scheduler isPsiphonTunnelConnected delivers its events on a background thread.
 */
- (RACSignal<NSNumber *> *)isPsiphonTunnelConnected;

@end

NS_ASSUME_NONNULL_END
