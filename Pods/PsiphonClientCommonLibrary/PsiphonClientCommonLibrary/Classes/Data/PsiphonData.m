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


#import "PsiphonData.h"


@implementation Throwable

@synthesize message = _message;
@synthesize stackTrace = _stackTrace;

- (id)init:(NSString*)msg withStackTrace:(NSArray*)trace {
    self = [super init];
    
    if (self) {
        _message = msg;
        _stackTrace = trace;
    }
    
    return self;
}

@end


@implementation DiagnosticEntry

@synthesize timestamp = _timestamp;
@synthesize message = _message;
@synthesize data = _data;

+ (DiagnosticEntry*)msg:(NSString*)msg {
    return [[DiagnosticEntry alloc] init:msg];
}

+ (DiagnosticEntry*)msg:(NSString*)msg andTimestamp:(NSDate*)timestamp {
    return [[DiagnosticEntry alloc] init:msg andTimestamp:timestamp];
}

- (id)init:(NSString*)msg nameValuePairs:(NSArray*)nameValuePairs {
    self = [super init];
    
    assert(nameValuePairs.count % 2 == 0);
    
    if (self) {
        _timestamp = [NSDate date];
        _message = msg;
        
        if (nameValuePairs != nil) {
            NSMutableDictionary *jsonObject = [[NSMutableDictionary alloc] init];
            
            for (NSUInteger i = 0; i <= [nameValuePairs count]/2 - 1; i++) {
                [jsonObject setObject:nameValuePairs[i*2+1] forKey:nameValuePairs[i*2]];
            }
            _data = jsonObject;
        }
    }
    
    return self;
}

- (id)init:(NSString*)msg {
    self = [super init];
    
    if (self) {
        DiagnosticEntry *result = [[DiagnosticEntry alloc] init:msg nameValuePairs:@[@"msg", msg]];
        _timestamp = result.timestamp;
        _message = result.message;
        _data = result.data;
    }
    
    return self;
}

- (id)init:(NSString*)msg andTimestamp:(NSDate*)timestamp {
    self = [super init];
    
    if (self) {
        DiagnosticEntry *result = [[DiagnosticEntry alloc] init:msg nameValuePairs:@[@"msg", msg]];
        
        _timestamp = timestamp;
        _message = result.message;
        _data = result.data;
    }
    
    return self;
}

- (NSString*)getTimestampISO8601 {
    return [PsiphonData dateToISO8601:self.timestamp];
}

- (NSString*)getTimestampForDisplay {
    return [PsiphonData timestampForDisplay:self.timestamp];
}

@end


@implementation StatusEntry

@synthesize timestamp = _timestamp;
@synthesize id = _id;
@synthesize sensitivity = _sensitivity;
@synthesize formatArgs = _formatArgs;
@synthesize throwable = _throwable;
@synthesize priority = _priority;

- (id)init:(NSString*)identifier
formatArgs:(NSArray*)formatArgs
 throwable:(Throwable*)throwable
sensitivity:(SensitivityLevel)sensitivity
  priority:(PriorityLevel)priority {
    self = [super init];
    
    if (self) {
        _timestamp = [NSDate date];
        _id = identifier;
        _sensitivity = sensitivity;
        _formatArgs = formatArgs;
        _throwable = throwable;
        _priority = priority;
    }
    
    return self;
}

- (NSString*)getTimestampISO8601 {
    return [PsiphonData dateToISO8601:_timestamp];
}

- (NSString*)getTimestampForDisplay {
    return [PsiphonData timestampForDisplay:_timestamp];
}

@end


@implementation PsiphonData {
    NSLock *diagnosticHistoryLock;
    NSLock *statusHistoryLock;
}

@synthesize diagnosticHistory = _diagnosticHistory;
@synthesize statusHistory = _statusHistory;

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}


/// The ISO8601DateFormatter class is only available in iOS 10.0+.
/// Follows format specified in `getISO8601String` https://github.com/Psiphon-Inc/psiphon-android/blob/d8575fc48aaf2e32f137ae25fa0705933234649b/app/src/main/java/com/psiphon3/psiphonlibrary/Utils.java#L631
/// http://stackoverflow.com/questions/28016578/swift-how-to-create-a-date-time-stamp-and-format-as-iso-8601-rfc-3339-utc-tim
+ (NSDateFormatter*)iso8601DateFormatter {
    static dispatch_once_t once;
    static NSDateFormatter *formatter;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; // https://developer.apple.com/library/mac/qa/qa1480/_index.html
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSX";
    });
    return formatter;
}


+ (NSString*)dateToISO8601:(NSDate*)date {
    return [[PsiphonData iso8601DateFormatter] stringFromDate:date];
}

+ (NSDate*)iso8601ToDate:(NSString*)iso8601Date {
    return [[PsiphonData iso8601DateFormatter] dateFromString:iso8601Date];
}

/**
 Convert timestamp to shortened human readible format for display.
 This method is thread-safe.
 */
+ (NSString*)timestampForDisplay:(NSDate*)timestamp {
    static dispatch_once_t once;
    static NSDateFormatter *formatter;
    
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale currentLocale];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });
    
    return [formatter stringFromDate:timestamp];
}

- (id)init {
    self = [super init];
    
    if (self) {
        statusHistoryLock = [[NSLock alloc] init];
        _statusHistory = [[NSMutableArray<StatusEntry*> alloc] init];
        diagnosticHistoryLock = [[NSLock alloc] init];
        _diagnosticHistory = [[NSMutableArray<DiagnosticEntry*> alloc] init];
    }
    
    return self;
}

// Notifier LogViewController that a new entry has been added
- (void)noticeLogAdded {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
         postNotificationName:@kDisplayLogEntry
         object:self
         userInfo:nil];
    });
}

- (void)addDiagnosticEntry:(DiagnosticEntry*)entry {
    [diagnosticHistoryLock lock];
    [_diagnosticHistory addObject:entry];
    [diagnosticHistoryLock unlock];
    [self noticeLogAdded];
}

- (void)addDiagnosticEntries:(NSArray<DiagnosticEntry*>*)entries {
    [diagnosticHistoryLock lock];
    [_diagnosticHistory addObjectsFromArray:entries];
    [diagnosticHistoryLock unlock];
    [self noticeLogAdded];
}

- (void)addStatusEntry:(StatusEntry*)entry {
    [statusHistoryLock lock];
    [_statusHistory addObject:entry];
    [statusHistoryLock unlock];
    [self noticeLogAdded];
}

- (NSArray<NSString*>*)getDiagnosticLogsForDisplay {
    NSMutableArray<NSString*> *logs = [[NSMutableArray<NSString*> alloc] init];
    
    [diagnosticHistoryLock lock];
    for (DiagnosticEntry* entry in _diagnosticHistory) {
        NSString *log = [NSString stringWithFormat:@"%@ %@", [entry getTimestampForDisplay], [entry message]];
        [logs addObject:log];
    }
    [diagnosticHistoryLock unlock];
    
    return logs;
}

// Return array of status entries formatted as strings for display
- (NSArray<NSString*>*)getStatusLogsForDisplay {
    NSMutableArray<NSString*> *logs = [[NSMutableArray<NSString*> alloc] init];
    
    [statusHistoryLock lock];
    for (StatusEntry* entry in _statusHistory) {
        if (entry.sensitivity != SensitivityLevelNotSensitive) {
            continue;
        }
        
        NSString *infoString = entry.id;
        
        // Apply format args to string if provided
        NSArray *formatArgs = entry.formatArgs;
        if (formatArgs != nil) {
            infoString = [PsiphonData stringWithFormat:infoString array:formatArgs];
        }
        // Generate string for display
        NSString *stringForDisplay = [NSString stringWithFormat:@"%@ %@", [entry getTimestampForDisplay], infoString];
        [logs addObject:stringForDisplay];
    }
    [statusHistoryLock unlock];
    return logs;
}

// http://stackoverflow.com/questions/1058736/how-to-create-a-nsstring-from-a-format-string-like-xxx-yyy-and-a-nsarr?noredirect=1&lq=1
+ (id)stringWithFormat:(NSString *)format array:(NSArray*) arguments
{
    if (arguments.count > 10) {
        @throw [NSException exceptionWithName:NSRangeException reason:@"Maximum of 10 arguments allowed" userInfo:@{@"collection": arguments}];
    }
    NSArray* a = [arguments arrayByAddingObjectsFromArray:@[@"X",@"X",@"X",@"X",@"X",@"X",@"X",@"X",@"X",@"X"]];
    return [NSString stringWithFormat:format, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10] ];
}

@end
