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

#import "PsiphonDataSharedDB.h"
#import "Logging.h"
#import "NSDate+PSIDateExtension.h"
#import "SharedConstants.h"
#import "FileUtils.h"
#import <PsiphonTunnel/PsiphonTunnel.h>

#pragma mark - NSUserDefaults Keys

UserDefaultsKey const EgressRegionsStringArrayKey = @"egress_regions";

UserDefaultsKey const ClientRegionStringKey = @"client_region";

UserDefaultsKey const TunnelStartTimeStringKey = @"tunnel_start_time";

UserDefaultsKey const TunnelSponsorIDStringKey = @"current_sponsor_id";

UserDefaultsKey const ServerTimestampStringKey = @"server_timestamp";

UserDefaultsKey const ExtensionVPNSessionNumberIntKey = @"extension_vpn_session_number";

UserDefaultsKey const ExtensionApplicationParametersDataKey = @"server_application_parameters_data";

UserDefaultsKey const ConstainerPurchaseRequiredVPNSessionHandledIntKey =
@"container_purchase_required_handled_vpn_session_num";

UserDefaultsKey const ExtensionIsZombieBoolKey = @"extension_zombie";

UserDefaultsKey const ContainerSharedDebugFlagsKey = @"SHARED_DEBUG_FLAGS";

UserDefaultsKey const ContainerForegroundStateBoolKey = @"container_foreground_state_bool_key";

UserDefaultsKey const ContainerTunnelIntentStatusIntKey = @"container_tunnel_intent_status_key";

UserDefaultsKey const ExtensionDisallowedTrafficAlertWriteSeqIntKey =
@"extension_disallowed_traffic_alert_write_seq_int";

UserDefaultsKey const ExtensionApplicationParametersChangeTimestamp =
@"extension_application_parameters_timestamp";

UserDefaultsKey const ContainerDisallowedTrafficAlertReadAtLeastUpToSeqIntKey =
@"container_disallowed_traffic_alert_read_at_least_up_to_seq_int";

UserDefaultsKey const TunnelEgressRegionKey = @"Tunnel-EgressRegion";

UserDefaultsKey const TunnelDisableTimeoutsKey = @"Tunnel-Disable-Timeouts";

UserDefaultsKey const TunnelUpstreamProxyURLKey = @"Tunnel-UpstreamProxyURL";

UserDefaultsKey const TunnelCustomHeadersKey = @"Tunnel-CustomHeaders";


/**
 * Key for boolean value that when TRUE indicates that the extension crashed before stop was called.
 * This value is only valid if the extension is not currently running.
 *
 * @note This does not indicate whether the extension crashed after the stop was called.
 * @attention This flag is set after the extension is started/stopped.
 */
UserDefaultsKey const SharedDataExtensionCrashedBeforeStopBoolKey = @"PsiphonDataSharedDB.ExtensionCrashedBeforeStopBoolKey";

#if DEBUG || DEV_RELEASE

UserDefaultsKey const DebugMemoryProfileBoolKey = @"PsiphonDataSharedDB.DebugMemoryProfilerBoolKey";
UserDefaultsKey const DebugPsiphonConnectionStateStringKey = @"PsiphonDataSharedDB.DebugPsiphonConnectionStateStringKey";

#endif

#pragma mark - Unused legacy keys
UserDefaultsKey const ContainerAuthorizationSetKey_Legacy = @"authorizations_container_key";

UserDefaultsKey const ContainerSubscriptionAuthorizationsDictKey_Legacy=
    @"subscription_authorizations_dict";

UserDefaultsKey const ExtensionRejectedSubscriptionAuthorizationIDsArrayKey_Legacy =
    @"extension_rejected_subscription_authorization_ids";

UserDefaultsKey const ExtensionRejectedSubscriptionAuthorizationIDsWriteSeqIntKey_Legacy =
@"extension_rejected_subscription_authorization_ids_write_seq_int";

UserDefaultsKey const ContainerRejectedSubscriptionAuthorizationIDsReadAtLeastUpToSeqIntKey_Legacy =
    @"container_read_rejected_subscription_authorization_ids_read_at_least_up_to_seq_int";

UserDefaultsKey const ContainerAppReceiptLatestSubscriptionExpiryDate_Legacy =
@"Container-Latest-Subscription-Expiry-Date";


#pragma mark -

@implementation Homepage
@end

@implementation PsiphonDataSharedDB {

    // NSUserDefaults objects are thread-safe.
    NSUserDefaults *sharedDefaults;

    NSString *appGroupIdentifier;
}

/*!
 * @brief Don't share an instance across threads.
 * @param identifier
 */
- (id)initForAppGroupIdentifier:(NSString*)identifier {
    self = [super init];
    if (self) {
        appGroupIdentifier = identifier;
        sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:identifier];
    }
    return self;
}

#pragma mark - Logging

// See comment in header
+ (NSURL *)dataRootDirectory {
    return [[[NSFileManager defaultManager]
             containerURLForSecurityApplicationGroupIdentifier:PsiphonAppGroupIdentifier]
            URLByAppendingPathComponent:@"com.psiphon3.ios.PsiphonTunnel"];
}

// See comment in header
- (NSString *)oldHomepageNoticesPath {
    return [[[[NSFileManager defaultManager]
            containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier] path]
            stringByAppendingPathComponent:@"homepage_notices"];
}

// See comment in header
- (NSString *)oldRotatingLogNoticesPath {
    return [[[[NSFileManager defaultManager]
            containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier] path]
            stringByAppendingPathComponent:@"rotating_notices"];
}

// See comment in header
- (NSString *)homepageNoticesPath {
    return [PsiphonTunnel homepageFilePath:[PsiphonDataSharedDB dataRootDirectory]].path;
}

// See comment in header
- (NSString *)rotatingLogNoticesPath {
    return [PsiphonTunnel noticesFilePath:[PsiphonDataSharedDB dataRootDirectory]].path;
}

// See comment in header
- (NSString *)rotatingOlderLogNoticesPath {
    return [PsiphonTunnel olderNoticesFilePath:[PsiphonDataSharedDB dataRootDirectory]].path;
}

#pragma mark - Tunnel core configs

- (NSString *_Nonnull)getEgressRegion {
    NSString *_Nullable egressRegion = [sharedDefaults stringForKey:TunnelEgressRegionKey];
    if (egressRegion == nil) {
        return kPsiphonRegionBestPerformance;
    }
    return egressRegion;
}

- (void)setEgressRegion:(NSString *_Nullable)regionCode {
    [sharedDefaults setObject:regionCode forKey:TunnelEgressRegionKey];
}

- (void)setDisableTimeouts:(BOOL)disableTimeouts {
    [sharedDefaults setBool:disableTimeouts forKey:TunnelDisableTimeoutsKey];
}

- (void)setUpstreamProxyURL:(NSString *_Nullable)url {
    [sharedDefaults setObject:url forKey:TunnelUpstreamProxyURLKey];
}

- (void)setCustomHttpHeaders:(NSDictionary *_Nullable)customHeaders {
    [sharedDefaults setObject:customHeaders forKey:TunnelCustomHeadersKey];
}

- (NSDictionary *)getTunnelCoreUserConfigs {
    
    NSMutableDictionary *userConfigs = [[NSMutableDictionary alloc] init];

    NSString *egressRegion = [sharedDefaults stringForKey:TunnelEgressRegionKey];
    if (egressRegion) {
        userConfigs[@"EgressRegion"] = egressRegion;
    }

    if ([sharedDefaults boolForKey:TunnelDisableTimeoutsKey]) {
        userConfigs[@"NetworkLatencyMultiplierLambda"] = @(0.1);
    }

    NSString *upstreamProxyUrl = [sharedDefaults stringForKey:TunnelUpstreamProxyURLKey];
    if (upstreamProxyUrl && [upstreamProxyUrl length] > 0) {
        userConfigs[@"UpstreamProxyUrl"] = upstreamProxyUrl;
    }

    id upstreamProxyCustomHeaders = [sharedDefaults objectForKey:TunnelCustomHeadersKey];
    if ([upstreamProxyCustomHeaders isKindOfClass:[NSDictionary class]]) {
        NSDictionary *customHeaders = (NSDictionary*)upstreamProxyCustomHeaders;
        if ([customHeaders count] > 0) {
            userConfigs[@"CustomHeaders"] = customHeaders;
        }
    }

    return userConfigs;
    
}

#pragma mark - Container Data (Data originating in the container)

- (BOOL)getAppForegroundState {
    return [sharedDefaults boolForKey:ContainerForegroundStateBoolKey];
}

- (BOOL)setAppForegroundState:(BOOL)foregrounded {
    [sharedDefaults setBool:foregrounded forKey:ContainerForegroundStateBoolKey];
    return [sharedDefaults synchronize];
}

- (NSInteger)getContainerTunnelIntentStatus {
    return [sharedDefaults integerForKey:ContainerTunnelIntentStatusIntKey];
}

#if !(TARGET_IS_EXTENSION)
- (void)setContainerTunnelIntentStatus:(NSInteger)statusCode {
    [sharedDefaults setInteger:statusCode forKey:ContainerTunnelIntentStatusIntKey];
}
#endif

- (NSDate *_Nullable)getContainerTunnelStartTime {
    NSString *_Nullable rfc3339Date = [sharedDefaults stringForKey:TunnelStartTimeStringKey];
    if (!rfc3339Date) {
        return nil;
    }

    return [NSDate fromRFC3339String:rfc3339Date];
}

- (void)setContainerTunnelStartTime:(NSDate *)startTime {
    NSString *rfc3339Date = [startTime RFC3339String];
    [sharedDefaults setObject:rfc3339Date forKey:TunnelStartTimeStringKey];
}

#if !(TARGET_IS_EXTENSION)
- (void)setContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum:(NSInteger)seq {
    [sharedDefaults setInteger:seq forKey:ContainerDisallowedTrafficAlertReadAtLeastUpToSeqIntKey];
}

- (NSInteger)getContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum {
    return [sharedDefaults integerForKey:ContainerDisallowedTrafficAlertReadAtLeastUpToSeqIntKey];
}

- (void)setContainerPurchaseRequiredHandledEventVPNSessionNumber:(NSInteger)sessionNum {
    [sharedDefaults setInteger:sessionNum forKey:ConstainerPurchaseRequiredVPNSessionHandledIntKey];
}

- (NSInteger)getContainerPurchaseRequiredHandledEventLatestVPNSessionNumber {
    return [sharedDefaults integerForKey:ConstainerPurchaseRequiredVPNSessionHandledIntKey];
}

#endif

#pragma mark - Extension Data (Data originating in the extension)

- (NSInteger)incrementVPNSessionNumber {
    NSInteger newValue = [self getVPNSessionNumber] + 1;
    [sharedDefaults setInteger:newValue
                        forKey:ExtensionVPNSessionNumberIntKey];
    return newValue;
}

- (NSInteger)getVPNSessionNumber {
    return [sharedDefaults integerForKey:ExtensionVPNSessionNumberIntKey];
}

- (PNEApplicationParameters *_Nonnull)getApplicationParameters {
    NSData *_Nullable data = [sharedDefaults dataForKey:ExtensionApplicationParametersDataKey];
    if (data == nil) {
        return [[PNEApplicationParameters alloc] init];
    }
    
    NSError *err = nil;
    
    id params = [NSKeyedUnarchiver unarchivedObjectOfClass:[PNEApplicationParameters class]
                                                  fromData:data
                                                     error:&err];
    
    if (err != nil) {
        [PsiFeedbackLogger error:err message:@"Failed to unarchive PNEApplicationParameters"];
        return [[PNEApplicationParameters alloc] init];
    } else {
        return (PNEApplicationParameters *)params;
    }
}

- (void)setApplicationParameters:(PNEApplicationParameters *_Nonnull)params {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:params
                                         requiringSecureCoding:TRUE
                                                         error:nil];
    if (data != nil) {
        [sharedDefaults setObject:data forKey:ExtensionApplicationParametersDataKey];
    }
}

// TODO: is timestamp needed? Maybe we can use this to detect staleness later
- (BOOL)setEmittedEgressRegions:(NSArray<NSString *> *)regions {
    [sharedDefaults setObject:regions forKey:EgressRegionsStringArrayKey];
    return [sharedDefaults synchronize];
}

- (BOOL)insertNewClientRegion:(NSString*)region {
    [sharedDefaults setObject:region forKey:ClientRegionStringKey];
    return [sharedDefaults synchronize];
}

- (BOOL)setCurrentSponsorId:(NSString *_Nullable)sponsorId {
    [sharedDefaults setObject:sponsorId forKey:TunnelSponsorIDStringKey];
    return [sharedDefaults synchronize];
}

- (void)updateServerTimestamp:(NSString*) timestamp {
    [sharedDefaults setObject:timestamp forKey:ServerTimestampStringKey];
    [sharedDefaults synchronize];
}

- (void)setExtensionIsZombie:(BOOL)isZombie {
    [sharedDefaults setBool:isZombie forKey:ExtensionIsZombieBoolKey];
}

- (BOOL)getExtensionIsZombie {
    return [sharedDefaults boolForKey:ExtensionIsZombieBoolKey];
}

- (void)incrementDisallowedTrafficAlertWriteSequenceNum {
    NSInteger lastSeq = [self getDisallowedTrafficAlertWriteSequenceNum];
    [sharedDefaults setInteger:(lastSeq + 1)
                        forKey:ExtensionDisallowedTrafficAlertWriteSeqIntKey];
}

- (NSInteger)getDisallowedTrafficAlertWriteSequenceNum {
    return [sharedDefaults integerForKey:ExtensionDisallowedTrafficAlertWriteSeqIntKey];
}

- (void)setApplicationParametersChangeTimestamp:(NSDate *)date {
    NSString *rfc3339Date = [date RFC3339String];
    [sharedDefaults setObject:rfc3339Date forKey:ExtensionApplicationParametersChangeTimestamp];
}

- (NSDate * _Nullable)getApplicationParametersChangeTimestamp {
    NSString * _Nullable rfc3339Date = [sharedDefaults stringForKey:ExtensionApplicationParametersChangeTimestamp];
    if (!rfc3339Date) {
        return nil;
    }
    return [NSDate fromRFC3339String:rfc3339Date];
}

- (NSArray<Homepage *> *_Nullable)getHomepages {
    NSMutableArray<Homepage *> *homepages = nil;
    NSError *err;

    NSString *data = [FileUtils tryReadingFile:[self homepageNoticesPath]];

    if (!data) {
        [PsiFeedbackLogger error:@"Failed reading homepage notices file. Error:%@", err];
        return nil;
    }

    homepages = [NSMutableArray array];
    NSArray *homepageNotices = [data componentsSeparatedByString:@"\n"];

    for (NSString *line in homepageNotices) {

        if (!line || [line length] == 0) {
            continue;
        }

        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0 error:&err];

        if (err) {
            [PsiFeedbackLogger error:@"Failed parsing homepage notices file. Error:%@", err];
        }

        if (dict) {
            Homepage *h = [[Homepage alloc] init];
            h.url = [NSURL URLWithString:dict[@"data"][@"url"]];
            h.timestamp = [NSDate fromRFC3339String:dict[@"timestamp"]];
            [homepages addObject:h];
        }
    }

    return homepages;
}

- (NSArray<NSString *> *)emittedEgressRegions {
    return [sharedDefaults objectForKey:EgressRegionsStringArrayKey];
}

- (NSString *)emittedClientRegion {
    return [sharedDefaults objectForKey:ClientRegionStringKey];
}

- (NSString *_Nullable)getCurrentSponsorId {
    return [sharedDefaults stringForKey:TunnelSponsorIDStringKey];
}

- (NSString*)getServerTimestamp {
    return [sharedDefaults stringForKey:ServerTimestampStringKey];
}

#pragma mark - Jetsam counter

- (NSString*)extensionJetsamMetricsFilePath {
    return [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier] path] stringByAppendingPathComponent:@"extension.jetsams"];
}

- (NSString*)extensionJetsamMetricsRotatedFilePath {
    return [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier] path] stringByAppendingPathComponent:@"extension.jetsams.1"];
}

#if TARGET_IS_CONTAINER

- (NSString*)containerJetsamMetricsRegistryFilePath {
    return [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier] path] stringByAppendingPathComponent:@"container.jetsam.registry"];
}

#endif

#if TARGET_IS_EXTENSION

- (void)setExtensionJetsammedBeforeStopFlag:(BOOL)crashed {
    [sharedDefaults setBool:crashed forKey:SharedDataExtensionCrashedBeforeStopBoolKey];
}

- (BOOL)getExtensionJetsammedBeforeStopFlag {
    return [sharedDefaults boolForKey:SharedDataExtensionCrashedBeforeStopBoolKey];
}

#endif

#pragma mark - Debug Preferences

#if DEBUG || DEV_RELEASE

- (SharedDebugFlags *_Nonnull)getSharedDebugFlags {
    NSData *_Nullable data = [sharedDefaults dataForKey:ContainerSharedDebugFlagsKey];
    if (data == nil) {
        return [[SharedDebugFlags alloc] init];
    } else {
        NSError *err = nil;
        id flags = [NSKeyedUnarchiver unarchivedObjectOfClass:[SharedDebugFlags class]
                                                     fromData:data
                                                        error:&err];
        if (err != nil) {
            return [[SharedDebugFlags alloc] init];
        } else {
            return (SharedDebugFlags *)flags;
        }
    }
}

- (void)setSharedDebugFlags:(SharedDebugFlags *_Nonnull)debugFlags {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:debugFlags
                                         requiringSecureCoding:TRUE
                                                         error:nil];
    if (data != nil) {
        [sharedDefaults setObject:data forKey:ContainerSharedDebugFlagsKey];
    }
}

- (void)setDebugMemoryProfiler:(BOOL)enabled {
    [sharedDefaults setBool:enabled forKey:DebugMemoryProfileBoolKey];
}

- (BOOL)getDebugMemoryProfiler {
    return [sharedDefaults boolForKey:DebugMemoryProfileBoolKey];
}

- (NSURL *)goProfileDirectory {
    return [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier]
            URLByAppendingPathComponent:@"go_profile" isDirectory:TRUE];
}

- (void)setDebugPsiphonConnectionState:(NSString *)state {
    [sharedDefaults setObject:state forKey:DebugPsiphonConnectionStateStringKey];
}

- (NSString *_Nonnull)getDebugPsiphonConnectionState {
    NSString *state = [sharedDefaults stringForKey:DebugPsiphonConnectionStateStringKey];
    if (state == nil) {
        state = @"None";
    }
    return state;
}

#endif

@end
