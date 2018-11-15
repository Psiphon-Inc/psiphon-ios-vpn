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

#if !(TARGET_IS_EXTENSION)
#import "PsiphonData.h"
#endif

@class Authorization;


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

- (NSString *)homepageNoticesPath;

- (NSString *)rotatingLogNoticesPath;

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

/**
 * @brief Returns previously persisted app foreground state from the shared NSUserDefaults
 *        NOTE: returns FALSE if no previous value was set using updateAppForegroundState:
 * @return TRUE if app if on the foreground, FALSE otherwise.
 */
- (BOOL)getAppForegroundState;

#if !(TARGET_IS_EXTENSION)

/**
 * @brief Sets app foreground state in shared NSSUserDefaults dictionary.
 *        NOTE: this method blocks until changes are written to disk.
 * @param foreground Whether app is on the foreground or not.
 * @return TRUE if change was persisted to disk successfully, FALSE otherwise.
 */
- (BOOL)updateAppForegroundState:(BOOL)foreground;

/*!
 * @brief Sets set of egress regions in standard NSUserDefaults
 */
- (void)setEmbeddedEgressRegions:(NSArray<NSString *> *_Nullable)regions;

/*!
 * @return NSArray of region codes.
 */
- (NSArray<NSString *> *_Nullable)embeddedEgressRegions;

#endif


#pragma mark - Extension Data (Data originating in the extension)

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

- (NSString *_Nullable)emittedClientRegion;

- (NSString *_Nullable)getCurrentSponsorId;

/**
 * @brief Returns previously persisted server timestamp from the shared NSUserDefaults
 * @return NSString* timestamp in RFC3339 format.
 */
- (NSString *_Nullable)getServerTimestamp;

#endif


#pragma mark - Subscription Receipt

#if TARGET_IS_EXTENSION

/**
 * Returns the file size of previously recorded empty receipt by the container (if any).
 * @return Nil or file size recorded by the container.
 */
- (NSNumber *_Nullable)getContainerEmptyReceiptFileSize;

#else

/**
 * If the receipt is empty (contains to transactions), the container should use
 * this method to set the receipt file size to be read by the network extension.
 * @param receiptFileSize File size of the empty receipt.
 */
- (void)setContainerEmptyReceiptFileSize:(NSNumber *_Nullable)receiptFileSize;

#endif


#pragma mark - Authorizations

#if TARGET_IS_EXTENSION

- (void)appendExpiredAuthorizationIDs:(NSSet<NSString *> *_Nullable)authsIDsToAppend;

- (void)markExpiredAuthorizationIDs:(NSSet<NSString *> *_Nullable)authorizations;

#else

- (void)setContainerAuthorizations:(NSSet<Authorization *> *_Nullable)authorizations;

#endif

- (NSSet<Authorization *> *)getContainerAuthorizations;

- (NSSet<Authorization *> *)getNonMarkedAuthorizations;

- (NSSet<NSString *> *)getMarkedExpiredAuthorizationIDs;


#pragma mark - Jetsam counter

#if TARGET_IS_EXTENSION

- (void)incrementJetsamCounter;

- (void)setExtensionJetsammedBeforeStopFlag:(BOOL)crashed;

- (BOOL)getExtensionJetsammedBeforeStopFlag;

- (NSInteger)getJetsamCounter;

#else

- (void)resetJetsamCounter;

#endif


#pragma mark - Debug Prefernces

#if DEBUG

- (void)setDebugMemoryProfiler:(BOOL)enabled;

- (BOOL)getDebugMemoryProfiler;

- (NSURL *)goProfileDirectory;

- (void)setDebugPsiphonConnectionState:(NSString *)state;

- (NSString *)getDebugPsiphonConnectionState;

#endif

@end

NS_ASSUME_NONNULL_END
