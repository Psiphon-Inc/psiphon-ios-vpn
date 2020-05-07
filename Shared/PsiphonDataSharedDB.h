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

#if !(TARGET_IS_EXTENSION)
#import "PsiphonData.h"
#endif

@class Authorization;

#pragma mark - NSUserDefaults Keys

extern UserDefaultsKey const _Nonnull EgressRegionsStringArrayKey;
extern UserDefaultsKey const _Nonnull ClientRegionStringKey;
extern UserDefaultsKey const _Nonnull TunnelStartTimeStringKey;
extern UserDefaultsKey const _Nonnull TunnelSponsorIDStringKey;
extern UserDefaultsKey const _Nonnull ServerTimestampStringKey;
extern UserDefaultsKey const _Nonnull ContainerAuthorizationSetKey;
extern UserDefaultsKey const _Nonnull ContainerSubscriptionAuthorizationsDictKey;
extern UserDefaultsKey const _Nonnull ExtensionRejectedSubscriptionAuthorizationIDsArrayKey;
extern UserDefaultsKey const _Nonnull ExtensionRejectedSubscriptionAuthorizationIDsWriteSeqIntKey;
extern UserDefaultsKey const _Nonnull ContainerRejectedSubscriptionAuthorizationIDsReadAtLeastUpToSeqIntKey;
extern UserDefaultsKey const _Nonnull ContainerForegroundStateBoolKey;
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

- (NSDictionary<NSString *, NSString *> *)objcFeedbackFields;

#pragma mark - Logging

/// Directory under which PsiphonTunnel is configured to store all of its files.
/// This directory must be created prior to starting PsiphonTunnel.
+ (NSURL *)dataRootDirectory;

/// Path for PsiphonTunnel to write homepage notices.
/// Deprecated:
/// PsiphonTunnel now stores all of its files under the configured data root directory.
/// This directory can be obtained with `homepageNoticesPath`.
/// PsiphonTunnel must be given a config with the `MigrateHompageNoticesFilename`
/// field set to this path to ensure that the homepage file at the old path is migrated to
/// the new location used by PsiphonTunnel.
- (NSString *)oldHomepageNoticesPath;


/// Path for PsiphonTunnel to write log notices.
/// Deprecated:
/// PsiphonTunnel now stores all of its files under the configured data root directory.
/// This directory can be obtained with `rotatingLogNoticesPath`.
/// PsiphonTunnel must be given a config with the `MigrateRotatingNoticesFilename`
/// field set to this path to ensure that the log notices file at the old path is migrated
/// to the new location used by PsiphonTunnel.
- (NSString *)oldRotatingLogNoticesPath;

/// Path at which PsiphonTunnel to writes homepage notices.
- (NSString *)homepageNoticesPath;

/// Path at which PsiphonTunnel to writes log notices.
- (NSString *)rotatingLogNoticesPath;

/// Path at which PsiphonTunnel will rotate log notices to.
- (NSString *)rotatingOlderLogNoticesPath;

#if !(TARGET_IS_EXTENSION)

+ (NSString *_Nullable)tryReadingFile:(NSString *)filePath;

/*!
 * If fileHandlePtr points to nil, then a new NSFileHandle for
 * reading filePath is created and fileHandlePtr is set to point to the new object.
 * If fileHandlePtr points to a NSFileHandle, it will be used for reading.
 * Reading operation is retried MAX_RETRIES more times if it fails for any reason,
 * while putting the thread to sleep for an amount of time defined by RETRY_SLEEP_TIME.
 * No errors are thrown if opening the file/reading operations fail.
 * @param filePath Path used to create a NSFileHandle if fileHandlePtr points to nil.
 * @param fileHandlePtr Pointer to existing NSFileHandle or nil.
 * @param bytesOffset The byte offset to seek to before reading.
 * @param readToOffset Populated with the file offset that was read to.
 * @return UTF8 string of read file content.
 */
+ (NSString *_Nullable)tryReadingFile:(NSString *)filePath
                      usingFileHandle:(NSFileHandle *_Nullable __strong *_Nonnull)fileHandlePtr
                       readFromOffset:(unsigned long long)bytesOffset
                         readToOffset:(unsigned long long *_Nullable)readToOffset;

- (void)readLogsData:(NSString *)logLines intoArray:(NSMutableArray<DiagnosticEntry *> *)entries;

- (NSArray<DiagnosticEntry*>*)getAllLogs;

#endif


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


#pragma mark - Extension Data (Data originating in the extension)

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
 * @brief Sets server timestamp in shared NSSUserDefaults dictionary.
 * @param timestamp from the handshake in RFC3339 format.
 * @return TRUE if change was persisted to disk successfully, FALSE otherwise.
 */
- (void)updateServerTimestamp:(NSString *)timestamp;

#else

- (NSArray<Homepage *> *_Nullable)getHomepages;

- (NSArray<NSString *> *_Nullable)emittedEgressRegions;

/**
 * @brief Returns previously persisted server timestamp from the shared NSUserDefaults
 * @return NSString* timestamp in RFC3339 format.
 */
- (NSString *_Nullable)getServerTimestamp;

#endif


#pragma mark - Authorizations

#if TARGET_IS_EXTENSION

- (void)removeNonSubscriptionAuthorizationsNotAccepted:(NSSet<NSString*>*_Nullable)authIdsToRemove;

#else

- (void)setNonSubscriptionEncodedAuthorizations:(NSSet<NSString*>*_Nullable)encodedAuthorizations;

- (void)appendNonSubscriptionEncodedAuthorization:(NSString *_Nonnull)base64Encoded;

#endif

- (NSSet<NSString *> *)getNonSubscriptionEncodedAuthorizations;

#pragma mark - Subscription Authorizations

#if !(TARGET_IS_EXTENSION)
/// Encoded object must JSON representation of type `[TransactionID: SubscriptionPurchaseAuth]`.
/// This method does no validation on the given `purchaseAuths`.
- (void)setSubscriptionAuths:(NSData *_Nullable)purchaseAuths;
#endif

/// Encoded object has JSON representation of type `[TransactionID: SubscriptionPurchaseAuth]`.
/// This method does no validation on the stored data.
- (NSData *_Nullable)getSubscriptionAuths;

-(NSArray<NSString *> *_Nonnull)getRejectedSubscriptionAuthorizationIDs;

#if TARGET_IS_EXTENSION
- (void)insertRejectedSubscriptionAuthorizationID:(NSString *)authorizationID;
#endif

- (NSInteger)getExtensionRejectedSubscriptionAuthIdWriteSequenceNumber;

- (NSInteger)getContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber;

#if !(TARGET_IS_EXTENSION)
- (void)setContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber:(NSInteger)seq;
#endif

#pragma mark - Jetsam counter

#if TARGET_IS_EXTENSION

- (void)incrementJetsamCounter;

- (void)setExtensionJetsammedBeforeStopFlag:(BOOL)crashed;

#else

- (void)resetJetsamCounter;

#endif

- (NSInteger)getJetsamCounter;

- (BOOL)getExtensionJetsammedBeforeStopFlag;

#pragma mark - Debug Preferences

#if DEBUG

- (void)setDebugMemoryProfiler:(BOOL)enabled;

- (BOOL)getDebugMemoryProfiler;

- (NSURL *)goProfileDirectory;

- (void)setDebugPsiphonConnectionState:(NSString *)state;

- (NSString *)getDebugPsiphonConnectionState;

#endif

@end

NS_ASSUME_NONNULL_END
