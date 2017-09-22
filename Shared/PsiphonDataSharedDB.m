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

#define MAX_LOG_LINES 250
#define SHARED_DATABASE_NAME @"psiphon_data_archive.db"

// ID
#define COL_ID @"_ID"

// Log Table
#define TABLE_LOG @"log"
#define COL_LOG_LOGJSON @"logjson"
#define COL_LOG_IS_DIAGNOSTIC @"is_diagnostic"
#define COL_LOG_TIMESTAMP @"timestamp"

// Homepages Table
#define TABLE_HOMEPAGE @"homepages"
#define COL_HOMEPAGE_URL @"url"
#define COL_HOMEPAGE_TIMESTAMP @"timestamp"

// Egress Regions Table
#define TABLE_EGRESS_REGIONS @"egress_regions"
#define COL_EGRESS_REGIONS_REGION_NAME @"url"
#define COL_EGRESS_REGIONS_TIMESTAMP @"timestamp"

/* NSUserDefaults keys */

#define TUN_CONNECTED_KEY @"tun_connected"
#define APP_FOREGROUND_KEY @"app_foreground"
#define SERVER_TIMESTAMP_KEY @"server_timestamp"

@implementation Homepage
@end

@implementation PsiphonDataSharedDB {
    NSUserDefaults *sharedDefaults;
    FMDatabaseQueue *q;

    NSString *appGroupIdentifier;
    NSString *databasePath;

    // Log Table
    int lastLogRowId;
    NSTimer *logTruncateTimer;
    NSLock *lastLogRowIdLock;
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
        COL_LOG_TIMESTAMP " TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

       "CREATE TABLE IF NOT EXISTS " TABLE_HOMEPAGE " ("
        COL_ID " INTEGER PRIMARY KEY AUTOINCREMENT, "
        COL_HOMEPAGE_URL " TEXT NOT NULL, "
        COL_HOMEPAGE_TIMESTAMP " TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

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

/*!
 * @brief Clears all tables in the database.
 * @return TRUE on success.
 */
- (BOOL)clearDatabase {
    NSString *CLEAR_TABLES =
      @"DELETE FROM " TABLE_LOG " ;"
       "DELETE FROM " TABLE_HOMEPAGE " ;";

    __block BOOL success = FALSE;
    [q inDatabase:^(FMDatabase *db) {
        success = [db executeStatements:CLEAR_TABLES];
        if (!success) {
            LOG_ERROR(@"%@", [db lastError]);
        }
    }];

    return success;
}

#pragma mark - Homepage Table methods

/*!
 * @brief Deletes previous set of homepages, then inserts new set of homepages.
 * @param homepageUrls
 * @return TRUE on success.
 */
- (BOOL)updateHomepages:(NSArray<NSString *> *)homepageUrls {
    __block BOOL success = FALSE;
    [q inTransaction:^(FMDatabase *db, BOOL *rollback) {
        success = [db executeUpdate:@"DELETE FROM " TABLE_HOMEPAGE " ;"];

        for (NSString *url in homepageUrls) {
            success |= [db executeUpdate:
              @"INSERT INTO " TABLE_HOMEPAGE " (" COL_HOMEPAGE_URL ") VALUES (?)", url, nil];
        }

        if (!success) {
            LOG_ERROR(@"Rolling back, error %@", [db lastError]);
            *rollback = TRUE;
            return;
        }
    }];

    return success;
}

/*!
 * @return NSArray of Homepages.
 */
- (NSArray<Homepage *> *)getAllHomepages {
    NSMutableArray<Homepage *> *homepages = [[NSMutableArray alloc] init];

    [q inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT * FROM " TABLE_HOMEPAGE];

        if (rs == nil) {
            LOG_ERROR(@"%@", [db lastError]);
            return;
        }

        while ([rs next]) {
            Homepage *homepage = [[Homepage alloc] init];
            homepage.url = [NSURL URLWithString:[rs stringForColumn:COL_HOMEPAGE_URL]];
            homepage.timestamp = [rs dateForColumn:COL_HOMEPAGE_TIMESTAMP];

            [homepages addObject:homepage];
        }

        [rs close];
    }];

    return homepages;
}

#pragma mark - Egress Regions Table methods

/*!
 * @brief Deletes previous set of regions, then inserts new set of regions.
 * @param regions
 * @return TRUE on success.
 */
// TODO: is timestamp needed? Maybe we can use this to detect staleness later
- (BOOL)insertNewEgressRegions:(NSArray<NSString *> *)regions {
    __block BOOL success = FALSE;
    [q inTransaction:^(FMDatabase *db, BOOL *rollback) {
        success = [db executeUpdate:@"DELETE FROM " TABLE_EGRESS_REGIONS " ;"];

        for (NSString *region in regions) {
            success |= [db executeUpdate:
                        @"INSERT INTO " TABLE_EGRESS_REGIONS " (" COL_EGRESS_REGIONS_REGION_NAME ") VALUES (?)", region, nil];
        }

        if (!success) {
            LOG_ERROR(@"Rolling back, error %@", [db lastError]);
            *rollback = TRUE;
            return;
        }
    }];

    return success;
}

/*!
 * @return NSArray of region codes.
 */
- (NSArray<NSString *> *)getAllEgressRegions {
    NSMutableArray<NSString *> *regions = [[NSMutableArray alloc] init];

    [q inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT * FROM " TABLE_EGRESS_REGIONS];

        if (rs == nil) {
            LOG_ERROR(@"%@", [db lastError]);
            return;
        }

        while ([rs next]) {
            NSString *region = [rs stringForColumn:COL_EGRESS_REGIONS_REGION_NAME];
            [regions addObject:region];
        }

        [rs close];
    }];

    return regions;
}

#pragma mark - Log Table methods

- (BOOL)insertDiagnosticMessage:(NSString*)message {
    __block BOOL success;
    [q inDatabase:^(FMDatabase *db) {
        NSError *err;

        success = [db executeUpdate:
          @"INSERT INTO " TABLE_LOG
          " (" COL_LOG_LOGJSON ", " COL_LOG_IS_DIAGNOSTIC ") VALUES (?,?)"
          withErrorAndBindings:&err, message, @YES, nil /* TODO */];

        if (!success) {
            LOG_ERROR(@"%@", err);
            // TODO: error handling/logging
        }
    }];
    return success;
}

- (void)truncateLogsOnInterval:(NSTimeInterval)interval {
    if (logTruncateTimer != nil) {
        [logTruncateTimer invalidate];
    }
    logTruncateTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                        target:self
                                                      selector:@selector(truncateLogs)
                                                      userInfo:nil
                                                       repeats:YES];

    // trigger timer to truncate logs immediately
    [logTruncateTimer fire];
}

- (BOOL)truncateLogs {
    // Truncate logs to MAX_LOG_LINES lines
    __block BOOL success = FALSE;

    [q inDatabase:^(FMDatabase *db) {
        NSError *err;
        success = [db executeUpdate:
          @"DELETE FROM " TABLE_LOG
          " WHERE " COL_ID " NOT IN "
          "(SELECT " COL_ID " FROM " TABLE_LOG " ORDER BY " COL_ID " DESC LIMIT (?));"
          withErrorAndBindings:&err, @MAX_LOG_LINES, nil];

        if (!success) {
            LOG_ERROR(@"%@", err);
            // TODO: error handling/logging
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

            NSDate *timestampDate = [PsiphonDataSharedDB dateFromTimestamp:timestampString];

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

#pragma mark - Server timestamp methods

/**
 * @brief Sets server timestamp in shared NSSUserDefaults dictionary.
 * @param timestamp from the handshake in RFC3339 format.
 * @return TRUE if change was persisted to disk successfully, FALSE otherwise.
 */
- (void)updateServerTimestamp:(NSString*) timestamp {
	[sharedDefaults setObject:timestamp forKey:SERVER_TIMESTAMP_KEY];
	[sharedDefaults synchronize];
}

/**
 * @brief Returns previously persisted server timestamp from the shared NSUserDefaults
 * @return NSString* timestamp in RFC3339 format.
 */
- (NSString*)getServerTimestamp {
	return [sharedDefaults stringForKey:SERVER_TIMESTAMP_KEY];
}

#pragma mark - Helper methods

+ (NSDate *)dateFromTimestamp:(NSString *)timestamp {
    NSDateFormatter * formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    return [formatter dateFromString:timestamp];
}

@end
