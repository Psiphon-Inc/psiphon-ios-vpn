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
#import "FMDB.h"
#import "Logging.h"
#import "NSDateFormatter+RFC3339.h"

#define TRUNCATE_AT_LOG_LINES 500
#define RETAIN_LOG_LINES 250
#define SHARED_DATABASE_NAME @"psiphon_data_archive.db"

// ID
#define COL_ID @"_ID"

// Log Table
#define TABLE_LOG @"log"
#define COL_LOG_LOGJSON @"logjson"
#define COL_LOG_IS_DIAGNOSTIC @"is_diagnostic"
#define COL_LOG_TIMESTAMP @"timestamp"

// Egress Regions Table
#define TABLE_EGRESS_REGIONS @"egress_regions"
#define COL_EGRESS_REGIONS_REGION_NAME @"url"
#define COL_EGRESS_REGIONS_TIMESTAMP @"timestamp"

/* Shared NSUserDefaults keys */
#define EGRESS_REGIONS_KEY @"egress_regions"
#define TUN_CONNECTED_KEY @"tun_connected"
#define APP_FOREGROUND_KEY @"app_foreground"


@implementation Homepage
@end

@implementation PsiphonDataSharedDB {
    NSUserDefaults *sharedDefaults;
    FMDatabaseQueue *q;

    NSString *appGroupIdentifier;
    NSString *databasePath;

    // Log Table
    int lastLogRowId;
    NSLock *lastLogRowIdLock;
    
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

        databasePath = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier] path];

        lastLogRowId = -1;
        lastLogRowIdLock = [[NSLock alloc] init];

        q = [FMDatabaseQueue databaseQueueWithPath:[databasePath stringByAppendingPathComponent:SHARED_DATABASE_NAME]];
        
        rfc3339Formatter = [NSDateFormatter createRFC3339Formatter];
    }
    return self;
}

#pragma mark - Database operations

- (BOOL)createDatabase {

    NSString *CREATE_TABLE_STATEMENTS =
      @"CREATE TABLE IF NOT EXISTS " TABLE_LOG " ("
        COL_ID " INTEGER PRIMARY KEY AUTOINCREMENT, "
        COL_LOG_LOGJSON " TEXT NOT NULL, "
        COL_LOG_IS_DIAGNOSTIC " BOOLEAN DEFAULT 0, "
        COL_LOG_TIMESTAMP " TEXT NOT NULL);"

        "CREATE TABLE IF NOT EXISTS " TABLE_EGRESS_REGIONS " ("
        COL_ID " INTEGER PRIMARY KEY AUTOINCREMENT, "
        COL_EGRESS_REGIONS_REGION_NAME " TEXT NOT NULL, "
        COL_EGRESS_REGIONS_TIMESTAMP " TIMESTAMP DEFAULT CURRENT_TIMESTAMP);";

    LOG_DEBUG(@"Create DATABASE");

    __block BOOL success = FALSE;
    [q inDatabase:^(FMDatabase *db) {
        success = [db executeStatements:CREATE_TABLE_STATEMENTS];
        if (!success) {
            LOG_ERROR(@"%@", [db lastError]);
        }
    }];

    return success;
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

- (BOOL)insertDiagnosticMessage:(NSString *)message withTimestamp:(NSString *)timestamp {

    // Truncates logs if necessary.
    [self truncateLogs];
    
    __block BOOL success;
    [q inDatabase:^(FMDatabase *db) {
        NSError *err;

        // TODO: IS_DIAGNOSTIC is always YES.
        success = [db executeUpdate:
          @"INSERT INTO " TABLE_LOG
          " (" COL_LOG_LOGJSON ", " COL_LOG_IS_DIAGNOSTIC ", " COL_LOG_TIMESTAMP ") VALUES (?,?,?)"
          withErrorAndBindings:&err, message, @YES, timestamp, nil];

        if (!success) {
            LOG_ERROR(@"%@", err);
            // TODO: error handling/logging
        }
    }];
    return success;
}

/**
 Truncates logs to RETAIN_LOG_LINES when number of log >= TRUNCATE_AT_LOG_LINES.
 @return TRUE if truncation proceeded and succeeded, FALSE otherwise.
 */
- (BOOL)truncateLogs {
    __block BOOL success = FALSE;

    [q inDatabase:^(FMDatabase *db) {
        NSError *err;
        
        int rows = [db intForQuery:@"SELECT COUNT(" COL_ID ") FROM " TABLE_LOG];
        
        if (rows >= TRUNCATE_AT_LOG_LINES) {
            success = [db executeUpdate:
                       @"DELETE FROM " TABLE_LOG
                       " WHERE " COL_ID " NOT IN "
                       "(SELECT " COL_ID " FROM " TABLE_LOG " ORDER BY " COL_ID " DESC LIMIT (?));"
                   withErrorAndBindings:&err, @RETAIN_LOG_LINES, nil];
            
            if (!success) {
                LOG_ERROR(@"%@", err);
                // TODO: error handling/logging
            }
        }
    }];

    return success;
}

#ifndef TARGET_IS_EXTENSION
- (NSArray<DiagnosticEntry*>*)getAllLogs {
    return [self getLogsNewerThanId:-1];
}

- (NSArray<DiagnosticEntry*>*)getNewLogs {
    return [self getLogsNewerThanId:lastLogRowId];
}

- (NSArray<DiagnosticEntry*>*)getLogsNewerThanId:(int)lastId {
    NSMutableArray<DiagnosticEntry*>* logs = [[NSMutableArray alloc] init];
    
    // Prevent fetching the same logs multiple times
    [lastLogRowIdLock lock];
    if (lastLogRowId > lastId) {
        [lastLogRowIdLock unlock];
        return nil;
    }
    
    [q inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT * FROM log WHERE _ID > (?);", @(lastId), nil];

        if (rs == nil) {
            LOG_ERROR(@"%@", [db lastError]);
            return;
        }

        while ([rs next]) {
            lastLogRowId = [rs intForColumn:COL_ID];

            NSString *timestampString = [rs stringForColumn:COL_LOG_TIMESTAMP];
            NSString *json = [rs stringForColumn:COL_LOG_LOGJSON];
//          BOOL isDiagnostic = [rs boolForColumn:COL_LOG_IS_DIAGNOSTIC]; // TODO

            NSDate *timestampDate = [rfc3339Formatter dateFromString:timestampString];
            if (!timestampDate) {
                // If the time storage format has changed, pass a date as a placeholder.
                // For now we don't need to convert old values into the new values.
                timestampDate = [NSDate dateWithTimeIntervalSince1970:0];
            }

            DiagnosticEntry *d = [[DiagnosticEntry alloc] init:json andTimestamp:timestampDate];
            [logs addObject:d];
        }

        [rs close];
    }];
    
    [lastLogRowIdLock unlock];

    return logs;
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
