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

NS_ASSUME_NONNULL_BEGIN

@class Authorization;

#pragma mark - Homepage data object

@interface Homepage : NSObject
@property (nonatomic) NSURL *url;
@property (nonatomic) NSDate *timestamp;
@end

#pragma mark - Psiphon shared DB with the extension

@interface PsiphonDataSharedDB : NSObject

- (id)initForAppGroupIdentifier:(NSString*)identifier;

#if !(TARGET_IS_EXTENSION)
+ (NSString *_Nullable)tryReadingFile:(NSString *)filePath;

+ (NSString *_Nullable)tryReadingFile:(NSString *)filePath
                      usingFileHandle:(NSFileHandle *_Nullable __strong *_Nonnull)fileHandlePtr
                       readFromOffset:(unsigned long long)bytesOffset
                         readToOffset:(unsigned long long *)readToOffset;

- (void)readLogsData:(NSString *)logLines intoArray:(NSMutableArray<DiagnosticEntry *> *)entries;

- (NSArray<Homepage *> *_Nullable)getHomepages;
#endif

- (BOOL)insertNewEgressRegions:(NSArray<NSString *> *)regions;

#if !(TARGET_IS_EXTENSION)
- (NSArray<NSString *> *_Nullable)embeddedAndEmittedEgressRegions;
- (void)setEmbeddedEgressRegions:(NSArray<NSString *> *_Nullable)regions;
- (NSArray<NSString *> *_Nullable)embeddedEgressRegions;
- (NSArray<NSString *> *_Nullable)emittedEgressRegions;
#endif

#if TARGET_IS_EXTENSION
- (BOOL)insertNewClientRegion:(NSString *_Nullable)region;
#else
- (NSString *_Nullable)emittedClientRegion;
#endif

- (NSString *)goProfileDirectory;
- (NSString *)homepageNoticesPath;
- (NSString *)rotatingLogNoticesPath;

#if !(TARGET_IS_EXTENSION)
- (NSArray<DiagnosticEntry*>*)getAllLogs;
#endif

- (BOOL)updateAppForegroundState:(BOOL)foreground;
- (BOOL)getAppForegroundState;

// Tunnel config state
#if TARGET_IS_EXTENSION
- (BOOL)setCurrentSponsorId:(NSString *_Nullable)sponsorId;
#else
- (NSString *_Nullable)getCurrentSponsorId;
#endif

// Server timestamp
- (void)updateServerTimestamp:(NSString *)timestamp;
- (NSString *_Nullable)getServerTimestamp;

// Receipt read by the container
#if !(TARGET_IS_EXTENSION)
- (void)setContainerEmptyReceiptFileSize:(NSNumber *_Nullable)receiptFileSize;
#endif

- (NSNumber *_Nullable)getContainerEmptyReceiptFileSize;

#pragma mark - Encoded Authorizations

#if !(TARGET_IS_EXTENSION)
- (void)setContainerAuthorizations:(NSSet<Authorization *> *_Nullable)authorizations;
#endif

- (NSSet<Authorization *> *)getContainerAuthorizations;
- (NSSet<Authorization *> *)getNonMarkedAuthorizations;
- (NSSet<NSString *> *)getMarkedExpiredAuthorizationIDs;

- (void)resetJetsamCounter;
- (void)incrementJetsamCounter;
/**
 * If TRUE and the extension is not running, the extension has crashed.
 */
- (BOOL)getExtensionJetsammedBeforeStopFlag;

#if TARGET_IS_EXTENSION
- (void)markExpiredAuthorizationIDs:(NSSet<NSString *> *_Nullable)authorizations;
- (void)appendExpiredAuthorizationIDs:(NSSet<NSString *> *_Nullable)authsIDsToAppend;
- (void)setExtensionJetsammedBeforeStopFlag:(BOOL)crashed;
- (NSInteger)getJetsamCounter;
#endif

#pragma mark - Debug Utils Prefernces

- (void)setDebugMemoryProfiler:(BOOL)enabled;
- (BOOL)getDebugMemoryProfiler;

@end

NS_ASSUME_NONNULL_END
