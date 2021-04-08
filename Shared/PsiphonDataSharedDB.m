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
#import <PsiphonTunnel/PsiphonTunnel.h>

#if TARGET_IS_EXTENSION
#import "Authorization.h"
#endif

// File operations parameters
#define MAX_RETRIES 3
#define RETRY_SLEEP_TIME 0.1f  // Sleep for 100 milliseconds.

#pragma mark - NSUserDefaults Keys

UserDefaultsKey const EgressRegionsStringArrayKey = @"egress_regions";

UserDefaultsKey const ClientRegionStringKey = @"client_region";

UserDefaultsKey const TunnelStartTimeStringKey = @"tunnel_start_time";

UserDefaultsKey const TunnelSponsorIDStringKey = @"current_sponsor_id";

UserDefaultsKey const ServerTimestampStringKey = @"server_timestamp";

UserDefaultsKey const ContainerAuthorizationSetKey = @"authorizations_container_key";

UserDefaultsKey const ExtensionIsZombieBoolKey = @"extension_zombie";

UserDefaultsKey const ContainerSubscriptionAuthorizationsDictKey =
    @"subscription_authorizations_dict";

UserDefaultsKey const ExtensionRejectedSubscriptionAuthorizationIDsArrayKey =
    @"extension_rejected_subscription_authorization_ids";

UserDefaultsKey const ExtensionRejectedSubscriptionAuthorizationIDsWriteSeqIntKey =
@"extension_rejected_subscription_authorization_ids_write_seq_int";

UserDefaultsKey const ContainerRejectedSubscriptionAuthorizationIDsReadAtLeastUpToSeqIntKey =
    @"container_read_rejected_subscription_authorization_ids_read_at_least_up_to_seq_int";

UserDefaultsKey const ContainerForegroundStateBoolKey =
@"container_foreground_state_bool_key";

UserDefaultsKey const ContainerTunnelIntentStatusIntKey = @"container_tunnel_intent_status_key";

UserDefaultsKey const ExtensionDisallowedTrafficAlertWriteSeqIntKey =
@"extension_disallowed_traffic_alert_write_seq_int";

UserDefaultsKey const ContainerDisallowedTrafficAlertReadAtLeastUpToSeqIntKey =
@"container_disallowed_traffic_alert_read_at_least_up_to_seq_int";

UserDefaultsKey const ContainerAppReceiptLatestSubscriptionExpiryDate =
@"Container-Latest-Subscription-Expiry-Date";

/**
 * Key for boolean value that when TRUE indicates that the extension crashed before stop was called.
 * This value is only valid if the extension is not currently running.
 *
 * @note This does not indicate whether the extension crashed after the stop was called.
 * @attention This flag is set after the extension is started/stopped.
 */
UserDefaultsKey const SharedDataExtensionCrashedBeforeStopBoolKey = @"PsiphonDataSharedDB.ExtensionCrashedBeforeStopBoolKey";

#if DEBUG

UserDefaultsKey const DebugMemoryProfileBoolKey = @"PsiphonDataSharedDB.DebugMemoryProfilerBoolKey";
UserDefaultsKey const DebugPsiphonConnectionStateStringKey = @"PsiphonDataSharedDB.DebugPsiphonConnectionStateStringKey";

#endif

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

+ (NSString *_Nullable)tryReadingFile:(NSString *_Nonnull)filePath {
    NSFileHandle *fileHandle;
    // NSFileHandle will close automatically when deallocated.
    return [PsiphonDataSharedDB tryReadingFile:filePath
                               usingFileHandle:&fileHandle
                                readFromOffset:0
                                  readToOffset:nil];
}

+ (NSString *_Nullable)tryReadingFile:(NSString *_Nonnull)filePath
                      usingFileHandle:(NSFileHandle *_Nullable __strong *_Nonnull)fileHandlePtr
                       readFromOffset:(unsigned long long)bytesOffset
                         readToOffset:(unsigned long long *_Nullable)readToOffset {

    NSData *fileData;
    NSError *err;

    for (int i = 0; i < MAX_RETRIES; ++i) {

        if (!(*fileHandlePtr)) {
            // NOTE: NSFileHandle created with fileHandleForReadingFromURL
            //       the handle owns its associated file descriptor, and will
            //       close it automatically when deallocated.
            (*fileHandlePtr) = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:filePath]
                                                                error:&err];
            if (err) {
                LOG_WARN(@"Error opening file handle for %@: Error: %@", filePath, err);
                // On failure explicitly setting fileHandlePtr to point to nil.
                (*fileHandlePtr) = nil;
            }
        }

        if ((*fileHandlePtr)) {
            @try {
                // From https://developer.apple.com/documentation/foundation/nsfilehandle/1413916-readdataoflength?language=objc
                // readDataToEndOfFile raises NSFileHandleOperationException if attempts
                // to determine file-handle type fail or if attempts to read from the file
                // or channel fail.
                [(*fileHandlePtr) seekToFileOffset:bytesOffset];
                fileData = [(*fileHandlePtr) readDataToEndOfFile];

                if (fileData) {
                    if (readToOffset) {
                        (*readToOffset) = [(*fileHandlePtr) offsetInFile];
                    }
                    return [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
                } else {
                    (*readToOffset) = (unsigned long long) 0;
                }
            }
            @catch (NSException *e) {
                [PsiFeedbackLogger error:@"Error reading file: %@", [e debugDescription]];

            }
        }

        // Put thread to sleep for 100 ms and try again.
        [NSThread sleepForTimeInterval:RETRY_SLEEP_TIME];
    }

    return nil;
}

// readLogsData tries to parse logLines, and for each JSON formatted line creates
// a DiagnosticEntry which is appended to entries.
// This method doesn't throw any errors on failure, and will log errors encountered.
#if !(TARGET_IS_EXTENSION)
- (void)readLogsData:(NSString *)logLines intoArray:(NSMutableArray<DiagnosticEntry *> *)entries {
    NSError *err;

    for (NSString *logLine in [logLines componentsSeparatedByString:@"\n"]) {

        if (!logLine || [logLine length] == 0) {
            continue;
        }

        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[logLine dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0 error:&err];
        if (err) {
            [PsiFeedbackLogger error:@"Failed to parse log line (%@). Error: %@", logLine, err];
        }

        if (dict) {
            // data key of dict dictionary, could either contains a dictionary, or another simple object.
            // In case the value is a dictionary, cannot rely on description method of dictionary, since it adds new-line characters
            // and semicolons to make it human-readable, but is unsuitable for our purposes.
            NSString *data = nil;
            if (![dict[@"data"] isKindOfClass:[NSDictionary class]]) {
                data = [dict[@"data"] description];
            } else {
                NSData *serializedDictionary = [NSJSONSerialization dataWithJSONObject:dict[@"data"] options:kNilOptions error:&err];
                data = [[NSString alloc] initWithData:serializedDictionary encoding:NSUTF8StringEncoding];
            }

            NSString *msg = nil;
            if (err) {
                [PsiFeedbackLogger error:@"Failed to serialize dictionary as JSON (%@)", dict[@"noticeType"]];
            } else {
                msg = [NSString stringWithFormat:@"%@: %@", dict[@"noticeType"], data];
            }

            NSDate *timestamp = [NSDate fromRFC3339String:dict[@"timestamp"]];

            if (!msg) {
                [PsiFeedbackLogger error:@"Failed to read notice message for log line (%@).", logLine];
                // Puts place holder value for message.
                msg = @"Failed to read notice message.";
            }

            if (!timestamp) {
                [PsiFeedbackLogger error:@"Failed to parse timestamp: (%@) for log line (%@)", dict[@"timestamp"], logLine];
                // Puts placeholder value for timestamp.
                timestamp = [NSDate dateWithTimeIntervalSince1970:0];
            }

            [entries addObject:[[DiagnosticEntry alloc] init:msg andTimestamp:timestamp]];
        }
    }
}
#endif

// Reads all log files and tries parses the json lines contained in each.
// This method is not meant to handle large files.
#if !(TARGET_IS_EXTENSION)
- (NSArray<DiagnosticEntry*> *_Nonnull)getAllLogs {

    LOG_DEBUG(@"Log filesize:%@", [self getFileSize:[self rotatingLogNoticesPath]]);
    LOG_DEBUG(@"Log backup filesize:%@", [self getFileSize:[self rotatingOlderLogNoticesPath]]);

    NSMutableArray<NSArray<DiagnosticEntry *> *> *entriesArray = [[NSMutableArray alloc] initWithCapacity:3];

    // Reads both tunnel-core log files all at once (max of 2MB) into memory,
    // and defers any processing after the read in order to reduce
    // the chance of a log rotation happening midway.

   NSArray<DiagnosticEntry *> *(^readRotatedLogs)(NSString *, NSString *) = ^(NSString *olderPath, NSString *newPath){
       NSMutableArray<DiagnosticEntry *> *entries = [[NSMutableArray alloc] init];
       NSString *tunnelCoreOlderLogs = [PsiphonDataSharedDB tryReadingFile:olderPath];
       NSString *tunnelCoreLogs = [PsiphonDataSharedDB tryReadingFile:newPath];
       [self readLogsData:tunnelCoreOlderLogs intoArray:entries];
       [self readLogsData:tunnelCoreLogs intoArray:entries];
       return entries;
   };

    entriesArray[0] = readRotatedLogs(self.rotatingOlderLogNoticesPath, self.rotatingLogNoticesPath);
    entriesArray[1] = readRotatedLogs(PsiFeedbackLogger.containerRotatingOlderLogNoticesPath,
            PsiFeedbackLogger.containerRotatingLogNoticesPath);
    entriesArray[2] = readRotatedLogs(PsiFeedbackLogger.extensionRotatingOlderLogNoticesPath,
            PsiFeedbackLogger.extensionRotatingLogNoticesPath);

    // Sorts classes of logs in entriesArray based on the timestamp of the last log in each class.
    NSArray *sortedEntriesArray = [entriesArray sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSDate *obj1LastTimestamp = [[(NSArray<DiagnosticEntry *> *) obj1 lastObject] timestamp];
        NSDate *obj2LastTimestamp = [[(NSArray<DiagnosticEntry *> *) obj2 lastObject] timestamp];
        return [obj2LastTimestamp compare:obj1LastTimestamp];
    }];

    // Calculates total number of logs and initializes an array of that size.
    NSUInteger totalNumLogs = 0;
    for (NSUInteger i = 0; i < [entriesArray count]; ++i) {
        totalNumLogs += [entriesArray[i] count];
    }

    NSMutableArray<DiagnosticEntry *> *allEntries = [[NSMutableArray alloc] initWithCapacity:totalNumLogs];

    for (NSUInteger j = 0; j < [sortedEntriesArray count]; ++j) {
        [allEntries addObjectsFromArray:sortedEntriesArray[j]];
    }

    return allEntries;
}
#endif

#pragma mark - Container Data (Data originating in the container)

- (NSDate *_Nullable)getAppReceiptLatestSubscriptionExpiryDate {
    return (NSDate *)[sharedDefaults objectForKey:ContainerAppReceiptLatestSubscriptionExpiryDate];
}

#if !(TARGET_IS_EXTENSION)
- (void)setAppReceiptLatestSubscriptionExpiryDate:(NSDate *_Nullable)date {
    [sharedDefaults setObject:date forKey:ContainerAppReceiptLatestSubscriptionExpiryDate];
}
#endif

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
#endif

#pragma mark - Extension Data (Data originating in the extension)

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

- (NSArray<Homepage *> *_Nullable)getHomepages {
    NSMutableArray<Homepage *> *homepages = nil;
    NSError *err;

    NSString *data = [PsiphonDataSharedDB tryReadingFile:[self homepageNoticesPath]];

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


#pragma mark - Authorizations

#if TARGET_IS_EXTENSION
- (void)removeNonSubscriptionAuthorizationsNotAccepted:(NSSet<NSString *> *_Nullable)authIdsToRemove {

    NSMutableSet<NSString *> *newEncodedAuths = [NSMutableSet set];

    [[self getNonSubscriptionEncodedAuthorizations]
     enumerateObjectsUsingBlock:^(NSString * _Nonnull encoded, BOOL * _Nonnull stop) {
        Authorization *_Nullable storedAuthorization = [[Authorization alloc]
                                                        initWithEncodedAuthorization:encoded];
        if (storedAuthorization == nil) {
            return;
        }
        
        if (![authIdsToRemove containsObject:storedAuthorization.ID]) {
            // storedAuthorization.ID doesn't match any of `authIdsToRemove`.
            [newEncodedAuths addObject:storedAuthorization.base64Representation];
        }

    }];

    [self setNonSubscriptionEncodedAuthorizations:newEncodedAuths];
}
#endif

- (void)setNonSubscriptionEncodedAuthorizations:(NSSet<NSString*>*_Nullable)encodedAuthorizations {
    // Persists Base64 representation of the Authorizations.
    [sharedDefaults setObject:encodedAuthorizations.allObjects
                       forKey:ContainerAuthorizationSetKey];
    [sharedDefaults synchronize];
}

- (NSSet<NSString *> *_Nonnull)getNonSubscriptionEncodedAuthorizations {
    NSArray<NSString *> *_Nullable encodedAuths = [sharedDefaults
                                                   stringArrayForKey:ContainerAuthorizationSetKey];
    if (encodedAuths == nil) {
        return [NSSet set];
    } else {
        return [NSSet setWithArray:encodedAuths];
    }
}

#pragma mark - Subscription

#if !(TARGET_IS_EXTENSION)
/// Encoded object must JSON representation of type `[SubscriptionPurchaseAuth]`.
- (void)setSubscriptionAuths:(NSData *_Nullable)purchaseAuths {
    [sharedDefaults setObject:purchaseAuths forKey:ContainerSubscriptionAuthorizationsDictKey];
}
#endif

- (NSData *_Nullable)getSubscriptionAuths {
    return [sharedDefaults dataForKey:ContainerSubscriptionAuthorizationsDictKey];
}

-(NSArray<NSString *> *_Nonnull)getRejectedSubscriptionAuthorizationIDs {
    NSArray<NSString *> *_Nullable storedValue =
        [sharedDefaults stringArrayForKey:ExtensionRejectedSubscriptionAuthorizationIDsArrayKey];
    
    if (storedValue == nil) {
        return [NSArray array];
    } else {
        return storedValue;
    }
}

#if TARGET_IS_EXTENSION
- (void)insertRejectedSubscriptionAuthorizationID:(NSString *)authorizationID {
    NSInteger extensionSeq = [self getExtensionRejectedSubscriptionAuthIdWriteSequenceNumber];
    NSInteger containerReadAtLeastToSeq =
      [self getContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber];
    
    NSMutableArray<NSString *> *rejectedAuthIDs;
    
    if (containerReadAtLeastToSeq < extensionSeq) {
        rejectedAuthIDs = [NSMutableArray arrayWithArray:[self getRejectedSubscriptionAuthorizationIDs]];
    } else {
        // Container is up-to-date with the extension.
        // Currently stored values for rejected subscription authorization ids can be removed.
        rejectedAuthIDs = [NSMutableArray array];
    }
    
    [rejectedAuthIDs addObject:authorizationID];
    
    // Updates the rejection authorization IDs before sequence number.
    // This guarantees that there is no data loss, and at most sequence number
    // will be out-of-sync.
    
    [sharedDefaults setObject:rejectedAuthIDs
                       forKey:ExtensionRejectedSubscriptionAuthorizationIDsArrayKey];
    
    [sharedDefaults setInteger:(extensionSeq + 1)
                        forKey:ExtensionRejectedSubscriptionAuthorizationIDsWriteSeqIntKey];
}
#endif

- (NSInteger)getExtensionRejectedSubscriptionAuthIdWriteSequenceNumber {
    NSInteger seq = [sharedDefaults
                     integerForKey:ExtensionRejectedSubscriptionAuthorizationIDsWriteSeqIntKey];
    return seq;
}

- (NSInteger)getContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber {
    NSInteger seq = [sharedDefaults
               integerForKey:ContainerRejectedSubscriptionAuthorizationIDsReadAtLeastUpToSeqIntKey];
    return seq;
}

#if !(TARGET_IS_EXTENSION)
- (void)setContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber:(NSInteger)seq {
    [sharedDefaults setInteger:seq
                      forKey:ContainerRejectedSubscriptionAuthorizationIDsReadAtLeastUpToSeqIntKey];
}
#endif

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

#if DEBUG

- (NSString *)getFileSize:(NSString *)filePath {
    NSError *err;
    unsigned long long byteCount = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&err] fileSize];
    if (err) { return nil;
    }
    return [NSByteCountFormatter stringFromByteCount:byteCount countStyle:NSByteCountFormatterCountStyleBinary];
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
