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

#define MAX_LOG_LINES 250
#define SHARED_DATABASE_NAME @"psiphon_data_archive.db"

// Log Table
#define TABLE_NAME_LOG @"log"
#define COLUMN_LOG_ID @"_ID"
#define COLUMN_LOG_LOGJSON @"logjson"
#define COLUMN_LOG_IS_DIAGNOSTIC @"is_diagnostic"
#define COLUMN_LOG_TIMESTAMP @"timestamp"

// Homepages Table
#define TABLE_NAME_HOMEPAGE @"homepages"
#define COLUMN_HOMEPAGE_ID @"_ID"
#define COLUMN_HOMEPAGE_URL @"url"
#define COLUMN_HOMEPAGE_TIMESTAMP @"timestamp"

// Egress Regions Table
#define TABLE_NAME_EGRESS_REGIONS @"egress_regions"
#define COLUMN_EGRESS_REGIONS_ID @"_ID"
#define COLUMN_EGRESS_REGIONS_REGION_NAME @"url"
#define COLUMN_EGRESS_REGIONS_TIMESTAMP @"timestamp"

@implementation Homepage
@end

@implementation PsiphonDataSharedDB {
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
      @"CREATE TABLE IF NOT EXISTS " TABLE_NAME_LOG " ("
        COLUMN_LOG_ID " INTEGER PRIMARY KEY AUTOINCREMENT, "
        COLUMN_LOG_LOGJSON " TEXT NOT NULL, "
        COLUMN_LOG_IS_DIAGNOSTIC " BOOLEAN DEFAULT 0, "
        COLUMN_LOG_TIMESTAMP " TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

        "CREATE TABLE IF NOT EXISTS " TABLE_NAME_HOMEPAGE " ("
        COLUMN_HOMEPAGE_ID " INTEGER PRIMARY KEY AUTOINCREMENT, "
        COLUMN_HOMEPAGE_URL " TEXT NOT NULL, "
        COLUMN_HOMEPAGE_TIMESTAMP " TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

        "CREATE TABLE IF NOT EXISTS " TABLE_NAME_EGRESS_REGIONS " ("
        COLUMN_EGRESS_REGIONS_ID " INTEGER PRIMARY KEY AUTOINCREMENT, "
        COLUMN_EGRESS_REGIONS_REGION_NAME " TEXT NOT NULL, "
        COLUMN_EGRESS_REGIONS_TIMESTAMP " TIMESTAMP DEFAULT CURRENT_TIMESTAMP);";

    NSLog(TAG @"Create DATABASE");
    
    __block BOOL success = FALSE;
    [q inDatabase:^(FMDatabase *db) {
        success = [db executeStatements:CREATE_TABLE_STATEMENTS];
        if (!success) {
            NSLog(TAG @"createDatabase: error %@", [db lastError]);
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
      @"DELETE FROM " TABLE_NAME_LOG " ;"
       "DELETE FROM " TABLE_NAME_HOMEPAGE " ;";

    __block BOOL success = FALSE;
    [q inDatabase:^(FMDatabase *db) {
        success = [db executeStatements:CLEAR_TABLES];
        if (!success) {
            NSLog(TAG @"clearDatabase error: %@", [db lastError]);
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
- (BOOL)insertNewHomepages:(NSArray<NSString *> *)homepageUrls {
    __block BOOL success = FALSE;
    [q inTransaction:^(FMDatabase *db, BOOL *rollback) {
        success = [db executeUpdate:@"DELETE FROM " TABLE_NAME_HOMEPAGE " ;"];

        for (NSString *url in homepageUrls) {
            success |= [db executeUpdate:
              @"INSERT INTO " TABLE_NAME_HOMEPAGE " (" COLUMN_HOMEPAGE_URL ") VALUES (?)", url, nil];
        }

        if (!success) {
            NSLog(TAG @"insertNewHomepages: rolling back, error %@", [db lastError]);
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
        FMResultSet *rs = [db executeQuery:@"SELECT * FROM " TABLE_NAME_HOMEPAGE];

        if (rs == nil) {
            NSLog(TAG @"getAllHomepages: error %@", [db lastError]);
            return;
        }

        while ([rs next]) {
            Homepage *homepage = [[Homepage alloc] init];
            homepage.url = [NSURL URLWithString:[rs stringForColumn:COLUMN_HOMEPAGE_URL]];
            homepage.timestamp = [rs dateForColumn:COLUMN_HOMEPAGE_TIMESTAMP];

            [homepages addObject:homepage];
        }
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
        success = [db executeUpdate:@"DELETE FROM " TABLE_NAME_EGRESS_REGIONS " ;"];

        for (NSString *region in regions) {
            success |= [db executeUpdate:
                        @"INSERT INTO " TABLE_NAME_EGRESS_REGIONS " (" COLUMN_EGRESS_REGIONS_REGION_NAME ") VALUES (?)", region, nil];
        }

        if (!success) {
            NSLog(TAG @"insertNewEgressRegions: rolling back, error %@", [db lastError]);
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
        FMResultSet *rs = [db executeQuery:@"SELECT * FROM " TABLE_NAME_EGRESS_REGIONS];

        if (rs == nil) {
            NSLog(TAG @"getAllEgressRegions: error %@", [db lastError]);
            return;
        }

        while ([rs next]) {
            NSString *region = [rs stringForColumn:COLUMN_EGRESS_REGIONS_REGION_NAME];
            [regions addObject:region];
        }
    }];

    return regions;
}

#pragma mark - Log Table methods

- (BOOL)insertDiagnosticMessage:(NSString*)message {
    __block BOOL success;
    [q inDatabase:^(FMDatabase *db) {
        NSError *err;

        success = [db executeUpdate:
          @"INSERT INTO " TABLE_NAME_LOG
          " (" COLUMN_LOG_LOGJSON ", " COLUMN_LOG_IS_DIAGNOSTIC ") VALUES (?,?)"
          withErrorAndBindings:&err, message, @YES, nil /* TODO */];

        if (!success) {
            NSLog(TAG @"insertDiagnosticMessage: error %@", err);
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
                   @"DELETE FROM " TABLE_NAME_LOG
                   " WHERE " COLUMN_LOG_ID " NOT IN "
                   "(SELECT " COLUMN_LOG_ID " FROM " TABLE_NAME_LOG " ORDER BY " COLUMN_LOG_ID " DESC LIMIT (?));"
               withErrorAndBindings:&err, @MAX_LOG_LINES, nil];

        if (!success) {
            NSLog(TAG @"truncateLogs: error %@", err);
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
            NSLog(TAG @"getLogsNewerThanId: error %@", [db lastError]);
            return;
        }

        while ([rs next]) {
            lastLogRowId = [rs intForColumn:COLUMN_LOG_ID];
            
            NSString *timestamp = [rs stringForColumn:COLUMN_LOG_TIMESTAMP];
            NSString *json = [rs stringForColumn:COLUMN_LOG_LOGJSON];
            //BOOL isDiagnostic = [rs boolForColumn:COLUMN_LOG_IS_DIAGNOSTIC]; // TODO

            DiagnosticEntry *d = [[DiagnosticEntry alloc] init:json andTimestamp:timestamp];
            [logs addObject:d];
        }
    }];
    [lastLogRowIdLock unlock];
    
    return logs;
}
#endif

@end
