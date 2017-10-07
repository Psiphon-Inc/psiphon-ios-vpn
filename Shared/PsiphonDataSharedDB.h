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
#ifndef TARGET_IS_EXTENSION
#import "PsiphonData.h"
#endif

@interface Homepage : NSObject
@property (nonatomic) NSURL *url;
@property (nonatomic) NSDate *timestamp;

@end

@interface PsiphonDataSharedDB : NSObject


- (id)initForAppGroupIdentifier:(NSString*)identifier;

#ifndef TARGET_IS_EXTENSION
+ (NSString *)tryReadingFile:(NSString *)filePath;
+ (NSString *)tryReadingFile:(NSString *)filePath fromOffset:(unsigned long long)bytesOffset offsetInFile:(unsigned long long  *)offsetInFile;
- (void)readLogsData:(NSString *)logLines intoArray:(NSMutableArray<DiagnosticEntry *> *)entries;
- (NSArray<Homepage *> *)getHomepages;
#endif

- (BOOL)insertNewEgressRegions:(NSArray<NSString *> *)regions;
- (NSArray<NSString *> *)getAllEgressRegions;

- (NSString *)homepageNoticesPath;

- (NSString *)rotatingLogNoticesPath;
#ifndef TARGET_IS_EXTENSION
- (NSArray<DiagnosticEntry*>*)getAllLogs;
#endif

- (BOOL)updateTunnelConnectedState:(BOOL)connected;
- (BOOL)getTunnelConnectedState;

- (BOOL)updateAppForegroundState:(BOOL)foreground;
- (BOOL)getAppForegroundState;

@end




