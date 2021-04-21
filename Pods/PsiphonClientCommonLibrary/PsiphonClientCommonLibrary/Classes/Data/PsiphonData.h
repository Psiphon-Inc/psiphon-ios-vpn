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

#ifndef PsiphonData_h
#define PsiphonData_h

#import <Foundation/Foundation.h>

#define kDisplayLogEntry "DisplayLogEntry"

typedef NS_ENUM(NSInteger, SensitivityLevel) {
    /**
     * The log does not contain sensitive information.
     */
    SensitivityLevelNotSensitive,
    /**
     * The log message itself is sensitive information.
     */
    SensitivityLevelSensitiveLog,
    /**
     * The format arguments to the log messages are sensitive, but the
     * log message itself is not.
     */
    SensitivityLevelSensitiveFormatArgs
};

typedef NS_ENUM(NSInteger, PriorityLevel) {
    PriorityVerbose,
    PriorityDebug,
    PriorityInfo,
    PriorityWarn,
    PriorityError,
    PriorityAssert
};

@interface Throwable : NSObject
- (id)init:(NSString*)msg withStackTrace:(NSArray*)trace;

@property (readonly, strong, nonatomic) NSArray *stackTrace; // Error.localizedDescription in most cases
@property (readonly, strong, nonatomic) NSString *message; // [NSThread callStackSymbols]
@end

@interface DiagnosticEntry : NSObject
+ (DiagnosticEntry*)msg:(NSString*)msg;
+ (DiagnosticEntry*)msg:(NSString*)msg andTimestamp:(NSDate*)timestamp;
- (id)init:(NSString*)msg;
- (id)init:(NSString*)msg andTimestamp:(NSDate*)timestamp;
- (NSString*)getTimestampForDisplay;
- (NSString*)getTimestampISO8601;

@property (readonly, strong, nonatomic) NSDictionary *data;
@property (readonly, strong, nonatomic) NSString *message;
@property (readonly, strong, nonatomic) NSDate *timestamp;
@end

@interface StatusEntry : NSObject
- (id)init:(NSString*)identifier
formatArgs:(NSArray*)formatArgs
 throwable:(Throwable*)throwable
sensitivity:(SensitivityLevel)sensitivity
  priority:(PriorityLevel)priority;
- (NSString*)getTimestampISO8601;

@property (readonly, strong, nonatomic) NSDate *timestamp;
@property (readonly, strong, nonatomic) NSArray *formatArgs;
@property (readonly, strong, nonatomic) NSString *id;
@property (readonly, nonatomic) PriorityLevel priority;
@property (readonly, nonatomic) SensitivityLevel sensitivity;
@property (readonly, strong, nonatomic) Throwable *throwable;
@end

@interface PsiphonData : NSObject
+ (instancetype)sharedInstance;
+ (NSString*)dateToISO8601:(NSDate*)date;
+ (NSDate*)iso8601ToDate:(NSString*)iso8601Date;
+ (NSString*)timestampForDisplay:(NSDate*)timestamp;

- (void)addDiagnosticEntry:(DiagnosticEntry*)entry;
- (void)addDiagnosticEntries:(NSArray<DiagnosticEntry*>*)entries;
- (void)addStatusEntry:(StatusEntry*)entry;
- (NSArray<NSString*>*)getDiagnosticLogsForDisplay;
- (NSArray<NSString*>*)getStatusLogsForDisplay;

@property (readonly, strong, nonatomic) NSMutableArray<DiagnosticEntry*> *diagnosticHistory;
@property (readonly, strong, nonatomic) NSMutableArray<StatusEntry*> *statusHistory;
@end

#endif /* PsiphonData_h */
