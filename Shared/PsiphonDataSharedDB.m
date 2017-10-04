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
#import "NSDateFormatter+RFC3339.h"

/* Shared NSUserDefaults keys */
#define EGRESS_REGIONS_KEY @"egress_regions"
#define TUN_CONNECTED_KEY @"tun_connected"
#define APP_FOREGROUND_KEY @"app_foreground"


@implementation Homepage
@end

@implementation PsiphonDataSharedDB {
    NSUserDefaults *sharedDefaults;

    NSString *appGroupIdentifier;

    // RFC3339 Date Formatter
    NSDateFormatter *rfc3339Formatter;
}

/*!
 * @brief Don't share an instance across threads.
 * @param identifier
 * @return
 */
- (id)initForAppGroupIdentifier:(NSString*)identifier {
    self = [super init];
    if (self) {
        appGroupIdentifier = identifier;

        sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:identifier];

        rfc3339Formatter = [NSDateFormatter createRFC3339MilliFormatter];
    }
    return self;
}

#pragma mark - Homepage methods

/*!
 * Reads shared homepages file.
 * @return NSArray of Homepages.
 */
- (NSArray<Homepage *> *)getHomepages {
    NSMutableArray<Homepage *> *homepages = [[NSMutableArray alloc] init];

    NSError *err;
    NSString *data = [NSString stringWithContentsOfFile:[self homepageNoticesPath]
                                               encoding:NSUTF8StringEncoding
                                                  error:&err];

    if (err) {
        LOG_ERROR(@"%@", err);
        return nil;
    }

    NSArray *homepageNotices = [data componentsSeparatedByString:@"\n"];
    for (NSString *line in homepageNotices) {
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0 error:&err];

        if (dict) {
            Homepage *h = [[Homepage alloc] init];
            h.url = [NSURL URLWithString:dict[@"data"][@"url"]];
            h.timestamp = [rfc3339Formatter dateFromString:dict[@"timestamp"]];
            [homepages addObject:h];
        }
    }

    return homepages;
}

- (NSString *)homepageNoticesPath {
    return [[[[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier] path]
      stringByAppendingPathComponent:@"homepage_notices"];
}

#pragma mark - Egress Regions Table methods

/*!
 * @brief Sets set of egress regions in shared NSUserDefaults
 * @param regions
 * @return TRUE if data was saved to disk successfully, otherwise FALSE.
 */
// TODO: is timestamp needed? Maybe we can use this to detect staleness later
- (BOOL)insertNewEgressRegions:(NSArray<NSString *> *)regions {
    [sharedDefaults setObject:regions forKey:EGRESS_REGIONS_KEY];
    return [sharedDefaults synchronize];
}

/*!
 * @return NSArray of region codes.
 */
- (NSArray<NSString *> *)getAllEgressRegions {
    return [sharedDefaults objectForKey:EGRESS_REGIONS_KEY];
}

#pragma mark - Log Table methods

- (NSString *)rotatingLogNoticesPath {
    return [[[[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier] path]
            stringByAppendingPathComponent:@"rotating_notices"];
}

- (NSString *)rotatingLogNoticesBackupPath {
    return [[self rotatingLogNoticesPath] stringByAppendingString:@".1"];
}

#ifndef TARGET_IS_EXTENSION

// Reads all log files and tries parses the json lines contained in each.
// This method is not meant to handle large files.
- (NSArray<DiagnosticEntry*>*)getAllLogs {

    NSMutableArray<DiagnosticEntry *> *entries = [[NSMutableArray alloc] init];

    NSString *backupLogLines = [self tryReadingFile:[NSURL fileURLWithPath:[self rotatingLogNoticesBackupPath]]];
    [self readLogsData:backupLogLines intoArray:entries];

    NSString *logLines = [self tryReadingFile:[NSURL fileURLWithPath:[self rotatingLogNoticesPath]]];
    [self readLogsData:logLines intoArray:entries];

    return entries;
}

// readLogsData tries to parse logLines, and for each JSON formatted line creates
// a DiagnosticEntry which is appended to entries.
// This method doesn't throw any errors on failure, and will log errors encountered.
- (void)readLogsData:(NSString *)logLines intoArray:(NSMutableArray<DiagnosticEntry *> *)entries {
    NSError *err;

    if (logLines) {
        for (NSString *logLine in [logLines componentsSeparatedByString:@"\n"]) {

            if (!logLine || [logLine length] == 0) {
                continue;
            }

            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[logLine dataUsingEncoding:NSUTF8StringEncoding]
                                                                 options:0 error:&err];
            if (err) {
                LOG_ERROR("Failed to parse log line (%@). Error: %@", logLine, err);
            }
            
            if (dict) {
                NSString *msg = [NSString stringWithFormat:@"%@: %@", dict[@"noticeType"],
                    [self getSimpleDictionaryDescription:dict[@"data"]]];
                NSDate *timestamp = [rfc3339Formatter dateFromString:dict[@"timestamp"]];

                if (!msg) {
                    LOG_ERROR("Failed to read notice message for log line (%@).", logLine);
                    // Puts place holder value for message.
                    msg = @"Failed to read notice message.";
                }

                if (!timestamp) {
                    LOG_ERROR("Failed to parse timestamp: (%@) for log line (%@)", dict[@"timestamp"], logLine);
                    // Puts placeholder value for timestamp.
                    timestamp = [NSDate dateWithTimeIntervalSince1970:0];
                }

                [entries addObject:[[DiagnosticEntry alloc] init:msg andTimestamp:timestamp]];
            }
        }
    }
}

// tryReadingFile opens file pointed to by fileUrl and tries to read its contentent.
// Reading operation is retried 2 more times if it fails for any reason.
// No errors are thrown if opening the file/reading operations fail.
- (NSString *)tryReadingFile:(NSURL *)fileUrl {
    NSData *fileData;
    NSError *err;

    for (int i = 0; i < 3; ++i) {

        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:fileUrl error:&err];

        if (err) {
            LOG_ERROR(@"Error opening file handle for %@: Error: %@", fileUrl, err);
        }

        // fileHandle is nil if no file exists at the provided path.
        if (!fileHandle) {
            return nil;
        }

        @try {
            // From https://developer.apple.com/documentation/foundation/nsfilehandle/1413916-readdataoflength?language=objc
            // readDataToEndOfFile raises NSFileHandleOperationException if attempts
            // to determine file-handle type fail or if attempts to read from the file
            // or channel fail.
            fileData = [fileHandle readDataToEndOfFile];

            if (fileData) {
                return [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
            }
        }
        @catch (NSException *e) {
            LOG_ERROR(@"Error reading file: %@", [e debugDescription]);
        }
        @finally {
            [fileHandle closeFile];
        }

        // Put thread to sleep for 100 ms and try again.
        [NSThread sleepForTimeInterval:0.1f];
    }

    return nil;
}


// This class returns a simple string representation of the dictionary dict.
// Unlike description method of NSDictionary, the string returned by this
// function doesn't include new-line character or semicolon.
- (NSString *)getSimpleDictionaryDescription:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return [dict description];
    }
    
    NSMutableString *desc = [NSMutableString string];
    [desc appendString:@"{"];
    NSArray *allKeys = [dict allKeys];
    for (NSUInteger i = 0; i < [allKeys count] ; ++i) {
        id object = dict[allKeys[i]];
        NSString *key = [allKeys[i] description];
        NSString *value;
        if ([object isKindOfClass:[NSDictionary class]]) {
            value = [self getSimpleDictionaryDescription:object];
        } else {
            value = [object description];
        }
        [desc appendString:[NSString stringWithFormat:@"%@:%@", key, value]];
        if (i < [allKeys count] - 1) {
            [desc appendString:@","];
        }
    }
    [desc appendString:@"}"];

    return desc;
}

#endif

#pragma mark - Tunnel State table methods

/**
 * @brief Sets tunnel connection state in shared NSUserDefaults dictionary.
 *        NOTE: This method blocks until changes are written to disk.
 * @param connected Tunnel core connected status.
 * @return TRUE if change was persisted to disk successfully, FALSE otherwise.
 */
- (BOOL)updateTunnelConnectedState:(BOOL)connected {
    [sharedDefaults setBool:connected forKey:TUN_CONNECTED_KEY];
    return [sharedDefaults synchronize];
}

/**
 * @brief Returns previously persisted tunnel state from the shared NSUserDefaults.
 *        This state is invalid if the network extension is not running.
 *        NOTE: returns FALSE if no previous value was set using updateTunnelConnectedState:
 * @return TRUE if tunnel is connected, FALSE otherwise.
 */
- (BOOL)getTunnelConnectedState {
    // Returns FALSE if no previous value was associated with this key.
    return [sharedDefaults boolForKey:TUN_CONNECTED_KEY];
}

# pragma mark - App State table methods

/**
 * @brief Sets app foreground state in shared NSSUserDefaults dictionary.
 *        NOTE: this method blocks until changes are written to disk.
 * @param foreground Whether app is on the foreground or not.
 * @return TRUE if change was persisted to disk successfully, FALSE otherwise.
 */
- (BOOL)updateAppForegroundState:(BOOL)foreground {
    [sharedDefaults setBool:foreground forKey:APP_FOREGROUND_KEY];
    return [sharedDefaults synchronize];
}

/**
 * @brief Returns previously persisted app foreground state from the shared NSUserDefaults
 *        NOTE: returns FALSE if no previous value was set using updateAppForegroundState:
 * @return TRUE if app if on the foreground, FALSE otherwise.
 */
- (BOOL)getAppForegroundState {
    return [sharedDefaults boolForKey:APP_FOREGROUND_KEY];
}

@end
