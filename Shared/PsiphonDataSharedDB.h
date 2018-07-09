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

@interface Homepage : NSObject

@property (nonatomic) NSURL *url;
@property (nonatomic) NSDate *timestamp;

@end


@interface PsiphonDataSharedDB : NSObject

- (id)initForAppGroupIdentifier:(NSString*)identifier;

#if !(TARGET_IS_EXTENSION)
+ (NSString *)tryReadingFile:(NSString *)filePath;
+ (NSString *)tryReadingFile:(NSString *)filePath usingFileHandle:(NSFileHandle *__strong *)fileHandlePtr readFromOffset:(unsigned long long)bytesOffset readToOffset:(unsigned long long *)readToOffset;
- (void)readLogsData:(NSString *)logLines intoArray:(NSMutableArray<DiagnosticEntry *> *)entries;
- (NSArray<Homepage *> *)getHomepages;
#endif

- (BOOL)insertNewEgressRegions:(NSArray<NSString *> *)regions;
#if !(TARGET_IS_EXTENSION)
- (NSArray<NSString *> *)embeddedAndEmittedEgressRegions;
- (void)insertNewEmbeddedEgressRegions:(NSArray<NSString *> *)regions;
- (NSArray<NSString *> *)embeddedEgressRegions;
- (NSArray<NSString *> *)emittedEgressRegions;
#endif

#if TARGET_IS_EXTENSION
- (BOOL)insertNewClientRegion:(NSString*)region;
#endif

#if !(TARGET_IS_EXTENSION)
- (NSString*)emittedClientRegion;
#endif


- (NSString *)homepageNoticesPath;
- (NSString *)rotatingLogNoticesPath;

#if !(TARGET_IS_EXTENSION)
- (NSArray<DiagnosticEntry*>*)getAllLogs;
#endif

- (BOOL)updateAppForegroundState:(BOOL)foreground;
- (BOOL)getAppForegroundState;

// Server timestamp
- (void)updateServerTimestamp:(NSString*)timestamp;
- (NSString*)getServerTimestamp;

// Receipt read by the container
#if !(TARGET_IS_EXTENSION)
- (void)setContainerEmptyReceiptFileSize:(NSNumber *)receiptFileSize;
#endif

- (NSNumber *)getContainerEmptyReceiptFileSize;

#pragma mark - Encoded Authorizations

#if !(TARGET_IS_EXTENSION)
- (void)setContainerAuthorizations:(NSSet<Authorization *> *)authorizations;
#endif

- (NSSet<Authorization *> *)getContainerAuthorizations;
- (NSSet<Authorization *> *)getNonMarkedAuthorizations;

#if TARGET_IS_EXTENSION
- (void)markExpiredAuthorizationIDs:(NSSet<NSString *> *)authorizations;
- (void)appendExpiredAuthorizationIDs:(NSSet<NSString *> *)authsToAppend;
#endif

- (NSSet<NSString *> *)getMarkedExpiredAuthorizationIDs;

@end
