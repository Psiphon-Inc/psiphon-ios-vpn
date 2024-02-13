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
#import "UserDefaults.h"
#import "PNEApplicationParameters.h"

#if !(TARGET_IS_EXTENSION)
#import "PsiphonData.h"
#endif

#if DEBUG || DEV_RELEASE
#import "SharedDebugFlags.h"
#endif

#pragma mark - Keys from PsiphonClientCommonLibrary

// Value re-defined from PsiphonClientCommonLibrary
#define kPsiphonRegionBestPerformance  @""

#pragma mark - NSUserDefaults Keys

extern UserDefaultsKey const _Nonnull EgressRegionsStringArrayKey;
extern UserDefaultsKey const _Nonnull ClientRegionStringKey;
extern UserDefaultsKey const _Nonnull TunnelStartTimeStringKey;
extern UserDefaultsKey const _Nonnull TunnelSponsorIDStringKey;
extern UserDefaultsKey const _Nonnull ServerTimestampStringKey;
extern UserDefaultsKey const _Nonnull ExtensionIsZombieBoolKey;
extern UserDefaultsKey const _Nonnull ExtensionStopReasonIntegerKey;
extern UserDefaultsKey const _Nonnull ContainerForegroundStateBoolKey;
extern UserDefaultsKey const _Nonnull ContainerTunnelIntentStatusIntKey;
extern UserDefaultsKey const _Nonnull ExtensionDisallowedTrafficAlertWriteSeqIntKey;
extern UserDefaultsKey const _Nonnull ContainerDisallowedTrafficAlertReadAtLeastUpToSeqIntKey;
extern UserDefaultsKey const _Nonnull SharedDataExtensionCrashedBeforeStopBoolKey;
extern UserDefaultsKey const _Nonnull SharedDataExtensionJetsamCounterIntegerKey;
extern UserDefaultsKey const _Nonnull DebugMemoryProfileBoolKey;
extern UserDefaultsKey const _Nonnull DebugPsiphonConnectionStateStringKey;


NS_ASSUME_NONNULL_BEGIN

#pragma mark - Homepage data object

@interface Homepage : NSObject
@property (nonatomic) NSURL *url;
@property (nonatomic) NSDate *timestamp;
@end


#pragma mark - Psiphon shared DB with the extension

@interface PsiphonDataSharedDB : NSObject

- (id)initForAppGroupIdentifier:(NSString*)identifier;

#pragma mark - Logging

/// Directory under which PsiphonTunnel is configured to store all of its files.
/// This directory must be created prior to starting PsiphonTunnel.
+ (NSURL *_Nullable)dataRootDirectory;

/// Path for PsiphonTunnel to write homepage notices.
/// Deprecated:
/// PsiphonTunnel now stores all of its files under the configured data root directory.
/// This directory can be obtained with `homepageNoticesPath`.
/// PsiphonTunnel must be given a config with the `MigrateHomepageNoticesFilename`
/// field set to this path to ensure that the homepage file at the old path is migrated to
/// the new location used by PsiphonTunnel.
- (NSString *_Nullable)oldHomepageNoticesPath;


/// Path for PsiphonTunnel to write log notices.
/// Deprecated:
/// PsiphonTunnel now stores all of its files under the configured data root directory.
/// This directory can be obtained with `rotatingLogNoticesPath`.
/// PsiphonTunnel must be given a config with the `MigrateRotatingNoticesFilename`
/// field set to this path to ensure that the log notices file at the old path is migrated
/// to the new location used by PsiphonTunnel.
- (NSString *_Nullable)oldRotatingLogNoticesPath;

/// Path at which PsiphonTunnel to writes homepage notices.
- (NSString *_Nullable)homepageNoticesPath;

/// Path at which PsiphonTunnel to writes log notices.
- (NSString *_Nullable)rotatingLogNoticesPath;

/// Path at which PsiphonTunnel will rotate log notices to.
- (NSString *_Nullable)rotatingOlderLogNoticesPath;

#pragma mark - Tunnel core configs

/**
 Retruns regions set by `-setEgressRegion:`.
 If the selected region was set to nil, returns best performance region.
 */
- (NSString *)getEgressRegion;

- (void)setEgressRegion:(NSString *_Nullable)regionCode;

- (void)setDisableTimeouts:(BOOL)disableTimeouts;

- (void)setUpstreamProxyURL:(NSString *_Nullable)url;

- (void)setCustomHttpHeaders:(NSDictionary *_Nullable)customHeaders;

/**
 Returns dictionary of tunnel core configs.
 */
- (NSDictionary *)getTunnelCoreUserConfigs;

#pragma mark - Container Data (Data originating in the container)

/** Returns last foreground state value written by the container.
 * - Note: The value is not ground truth and might be stale if e.g. the container crashes.
 */
- (BOOL)getAppForegroundState;

#if !(TARGET_IS_EXTENSION)
/** Sets app foregrounded state. This state is used by the network extension.
 */
- (BOOL)setAppForegroundState:(BOOL)foregrounded;
#endif

/** Returns the last `TunnelStartStopIntent` written by the container.
The integer values are defined in `NEBridge.h` with prefix `TUNNEL_INTENT_`.
 */
- (NSInteger)getContainerTunnelIntentStatus;

#if !(TARGET_IS_EXTENSION)
/** Sets the `TunnelStartStopIntent` status to be used by the tunnel provider.
 Values should be one of the constants defined in `NEBrdige.h` starting with prefix `TUNNEL_INTENT_`.
 */
- (void)setContainerTunnelIntentStatus:(NSInteger)statusCode;
#endif

/**
 * Last date/time immediately before the extension was last started from the container.
 * Check where `setContainerTunnelStartTime:` is called to set the last tunnel start time.
 *
 * @return NSDate of when tunnel was started by the container. Null if no value is set.
 */
- (NSDate *_Nullable)getContainerTunnelStartTime;

#if !(TARGET_IS_EXTENSION)

/**
 * Time immediately before the extension is started from the tunnel.
 */
- (void)setContainerTunnelStartTime:(NSDate *)startTime;

#endif

#if !(TARGET_IS_EXTENSION)

// Disallowed traffic alert
- (void)setContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum:(NSInteger)seq;
- (NSInteger)getContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum;

// Purchase requried prompt handled vpn session number.
- (void)setContainerPurchaseRequiredHandledEventVPNSessionNumber:(NSInteger)sessionNum;
- (NSInteger)getContainerPurchaseRequiredHandledEventLatestVPNSessionNumber;

#endif

#pragma mark - Extension Data (Data originating in the extension)

#if TARGET_IS_EXTENSION
// Returns updated VPN session number.
- (NSInteger)incrementVPNSessionNumber;
#endif
- (NSInteger)getVPNSessionNumber;

- (PNEApplicationParameters *_Nonnull)getApplicationParameters;
#if TARGET_IS_EXTENSION
// Overrides previously persisted application parameters.
// Returns an non-nil error if archiving params failed.
- (NSError *_Nullable)setApplicationParameters:(PNEApplicationParameters *_Nonnull)params;
#endif

- (NSString *_Nullable)emittedClientRegion;

- (NSString *_Nullable)getCurrentSponsorId;


#if TARGET_IS_EXTENSION

/*!
 * @brief Sets set of egress regions in shared NSUserDefaults
 * @param regions
 * @return TRUE if data was saved to disk successfully, otherwise FALSE.
 */
- (BOOL)setEmittedEgressRegions:(NSArray<NSString *> *)regions;

/*!
 * @brief Sets client region in shared NSUserDefaults
 * @param region
 * @return TRUE if data was saved to disk successfully, otherwise FALSE.
 */
- (BOOL)insertNewClientRegion:(NSString *_Nullable)region;

- (BOOL)setCurrentSponsorId:(NSString *_Nullable)sponsorId;

/**
 * @brief Sets server timestamp in shared NSUserDefaults dictionary.
 * @param timestamp from the handshake in RFC3339 format.
 * @return TRUE if change was persisted to disk successfully, FALSE otherwise.
 */
- (void)updateServerTimestamp:(NSString *)timestamp;

/**
 * Set by the extension when initialized.
 */
- (void)setExtensionIsZombie:(BOOL)isZombie;

#else

- (NSArray<Homepage *> *_Nullable)getHomepages;

- (NSArray<NSString *> *_Nullable)emittedEgressRegions;

/**
 * @brief Returns previously persisted server timestamp from the shared NSUserDefaults
 * @return NSString* timestamp in RFC3339 format.
 */
- (NSString *_Nullable)getServerTimestamp;

#endif

/**
 * Returns last value recorded by the extension with call to `setExtensionIsZombie:`.
 */
- (BOOL)getExtensionIsZombie;

#if TARGET_IS_EXTENSION
/**
 * @brief Sets extension stop reason in shared NSUserDefaults. Called by the extension when
 * stopped.
 * @param stopReason Provider stop reason. See NEProviderStopReason.
 */
- (void)setExtensionStopReason:(NSInteger)stopReason;

/**
 * @return Previously persisted NEProviderStopReason in shared NSUserDefaults, which is the
 * reason the extension was last stopped. Returns 0 if the the extension has not been stopped yet,
 * which is the same as NEProviderStopReasonNone; i.e. first run of the extension after as fresh
 * install or a subsequent run if the extension continues to jetsam before it is stopped.
 */
- (NSInteger)getExtensionStopReason;
#endif

#if TARGET_IS_EXTENSION
- (void)incrementDisallowedTrafficAlertWriteSequenceNum;
#endif

- (NSInteger)getDisallowedTrafficAlertWriteSequenceNum;

#if TARGET_IS_EXTENSION
- (void)setApplicationParametersChangeTimestamp:(NSDate *)date;
#endif
- (NSDate * _Nullable)getApplicationParametersChangeTimestamp;

#pragma mark - Jetsam counter

- (NSString*)extensionJetsamMetricsFilePath;

- (NSString*)extensionJetsamMetricsRotatedFilePath;

#if TARGET_IS_CONTAINER

- (NSString *)containerJetsamMetricsRegistryFilePath;

#endif

#if TARGET_IS_EXTENSION

- (void)setExtensionJetsammedBeforeStopFlag:(BOOL)crashed;

- (BOOL)getExtensionJetsammedBeforeStopFlag;

#endif

#pragma mark - Debug Preferences

#if DEBUG || DEV_RELEASE

- (SharedDebugFlags *_Nonnull)getSharedDebugFlags;

- (void)setSharedDebugFlags:(SharedDebugFlags *_Nonnull)debugFlags;

- (void)setDebugMemoryProfiler:(BOOL)enabled;

- (BOOL)getDebugMemoryProfiler;

- (NSURL *)goProfileDirectory;

- (void)setDebugPsiphonConnectionState:(NSString *)state;

- (NSString *)getDebugPsiphonConnectionState;

#endif

@end

NS_ASSUME_NONNULL_END
