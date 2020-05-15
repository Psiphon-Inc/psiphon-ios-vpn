/*
 * Copyright (c) 2020, Psiphon Inc.
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

#import <XCTest/XCTest.h>
#import "JetsamTracking.h"
#import "JetsamEvent.h"
#import "RunningStat.h"

@interface JetsamTrackingTest : XCTestCase

@end

@implementation JetsamTrackingTest

/// Test writing jetsam events from the extension's perspective
/// and reading back the aggregate metrics from the container's perspective.
- (void)testWritingAndReading {

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSError *err;
    NSURL *dir = [fileManager URLForDirectory:NSDocumentDirectory
                                     inDomain:NSUserDomainMask
                            appropriateForURL:nil
                                       create:NO
                                        error:&err];
    if (err != nil) {
        XCTFail(@"Failed to get dir: %@", err);
        return;
    }

    NSString *filePath = [dir URLByAppendingPathComponent:@"file"].path;
    NSString *olderFilePath = [dir URLByAppendingPathComponent:@"file.1"].path;
    NSString *registryFilePath = [dir URLByAppendingPathComponent:@"registry"].path;

    // cleanup previous run
    [fileManager removeItemAtPath:filePath error:nil];
    [fileManager removeItemAtPath:olderFilePath error:nil];
    [fileManager removeItemAtPath:registryFilePath error:nil];

    NSArray<JetsamEvent*>* jetsams = @[
        [JetsamEvent jetsamEventWithAppVersion:@"1" runningTime:10 jetsamDate:NSDate.date.timeIntervalSince1970 + 0],
        [JetsamEvent jetsamEventWithAppVersion:@"1" runningTime:100 jetsamDate:NSDate.date.timeIntervalSince1970 + 10],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:NSDate.date.timeIntervalSince1970 + 20],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:NSDate.date.timeIntervalSince1970 + 30],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:NSDate.date.timeIntervalSince1970 + 50],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:NSDate.date.timeIntervalSince1970 + 60],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:NSDate.date.timeIntervalSince1970 - 60 /* should not be counted */]
    ];

    NSArray<BinRange*>* binRanges = @[
        [BinRange binRangeWithRange:MakeCBinRange(0, 10)],
        [BinRange binRangeWithRange:MakeCBinRange(10, DBL_MAX)],
    ];

    NSMutableDictionary<NSString*, JetsamPerAppVersionStat*>* expectedMetrics = [[NSMutableDictionary alloc] init];
    JetsamEvent *prevJetsam = nil;

    for (JetsamEvent *jetsam in jetsams) {
        [ExtensionJetsamTracking logJetsamEvent:jetsam
                                     toFilepath:filePath
                            withRotatedFilepath:olderFilePath
                               maxFilesizeBytes:1e6
                                          error:&err];
        if (err != nil) {
            XCTFail(@"Unexpected error: %@", err);
            return;
        }

        // Mirror jetsam tracking stat calculation
        JetsamPerAppVersionStat *stat = [expectedMetrics objectForKey:jetsam.appVersion];
        if (stat == nil) {
            stat = [[JetsamPerAppVersionStat alloc] init];
        }

        if (stat.runningTime == nil) {
            stat.runningTime = [[RunningStat alloc] initWithValue:jetsam.runningTime binRanges:binRanges];
        } else {
            [stat.runningTime addValue:jetsam.runningTime];
        }

        if (prevJetsam != nil && [prevJetsam.appVersion isEqualToString:jetsam.appVersion]) {
            // Round to the nearest second
            NSTimeInterval timeSinceLastJetsam = round(jetsam.jetsamDate - prevJetsam.jetsamDate);
            if (timeSinceLastJetsam >= 0) {
                if (stat.timeBetweenJetsams == nil) {
                    stat.timeBetweenJetsams = [[RunningStat alloc] initWithValue:timeSinceLastJetsam binRanges:binRanges];
                } else {
                    [stat.timeBetweenJetsams addValue:timeSinceLastJetsam];
                }
            }
        }

        [expectedMetrics setObject:stat forKey:jetsam.appVersion];

        prevJetsam = jetsam;
    }

    JetsamMetrics *metrics = [ContainerJetsamTracking getMetricsFromFilePath:filePath
                                                         withRotatedFilepath:olderFilePath
                                                            registryFilepath:registryFilePath
                                                               readChunkSize:32
                                                                   binRanges:binRanges
                                                                       error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    if (![metrics.perVersionMetrics isEqualToDictionary:expectedMetrics]) {
        XCTFail(@"Did not get expected per version metrics");
        NSLog(@"Got:");
        [self printPerVersionMetrics:metrics.perVersionMetrics];
        NSLog(@"Expected:");
        [self printPerVersionMetrics:expectedMetrics];
        return;
    }

    // Confirm that next metric is empty since all the Jetsam events
    // have been read and the file registry persisted.

    metrics = [ContainerJetsamTracking getMetricsFromFilePath:filePath
                                          withRotatedFilepath:olderFilePath
                                             registryFilepath:registryFilePath
                                                readChunkSize:32
                                                    binRanges:binRanges
                                                        error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    if (![metrics.perVersionMetrics isEqualToDictionary:@{}]) {
        XCTFail(@"Expected per version metrics to be empty");
        NSLog(@"Got:");
        [self printPerVersionMetrics:metrics.perVersionMetrics];
        return;
    }
}

/// Test corrupting the jetsam log file. The container reader should return an error.
- (void)testFileCorruption {

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSError *err;
    NSURL *dir = [fileManager URLForDirectory:NSDocumentDirectory
                                     inDomain:NSUserDomainMask
                            appropriateForURL:nil
                                       create:NO
                                        error:&err];
    if (err != nil) {
        XCTFail(@"Failed to get dir: %@", err);
        return;
    }

    NSString *filePath = [dir URLByAppendingPathComponent:@"file"].path;
    NSString *olderFilePath = [dir URLByAppendingPathComponent:@"file.1"].path;
    NSString *registryFilePath = [dir URLByAppendingPathComponent:@"registry"].path;

    // cleanup previous run
    [fileManager removeItemAtPath:filePath error:nil];
    [fileManager removeItemAtPath:olderFilePath error:nil];
    [fileManager removeItemAtPath:registryFilePath error:nil];

    NSArray<JetsamEvent*>* jetsams = @[
        [JetsamEvent jetsamEventWithAppVersion:@"1" runningTime:10 jetsamDate:[NSDate.date timeIntervalSince1970]],
    ];

    for (JetsamEvent *jetsam in jetsams) {
        [ExtensionJetsamTracking logJetsamEvent:jetsam
                                     toFilepath:filePath
                            withRotatedFilepath:olderFilePath
                               maxFilesizeBytes:1e6
                                          error:&err];
        if (err != nil) {
            XCTFail(@"Unexpected error: %@", err);
            return;
        }
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:filePath];
    void *garbage_bytes = (void*)malloc(sizeof(1024));
    [fh writeData:[NSData dataWithBytes:garbage_bytes length:1024]];
    free(garbage_bytes);

    JetsamMetrics *metrics = [ContainerJetsamTracking getMetricsFromFilePath:filePath
                                                         withRotatedFilepath:olderFilePath
                                                            registryFilepath:registryFilePath
                                                               readChunkSize:32
                                                                   binRanges:nil
                                                                       error:&err];
    if (err == nil) {
        XCTFail(@"Unexpected error");
        return;
    }

    XCTAssertNil(metrics);
    XCTAssertEqual(err.domain, ContainerJetsamTrackingErrorDomain);
    XCTAssertEqual(err.code, ContainerJetsamTrackingErrorDecodingDataFailed);
}


#pragma mark - Helpers

- (void)printPerVersionMetrics:(NSDictionary<NSString*, JetsamPerAppVersionStat*>*)perVersionMetrics {
    for (NSString *key in perVersionMetrics) {

        RunningStat *runningTime = [perVersionMetrics objectForKey:key].runningTime;
        if (runningTime != nil) {
            NSLog(@"RunningTime - (v%@) count: %d, min: %f, max: %f, stdev: %f, bins: %@",
                  key, runningTime.count, runningTime.min, runningTime.max,
                  [runningTime stdev], runningTime.talliedBins);
        }

        RunningStat *timeBetweenJetsams = [perVersionMetrics objectForKey:key].timeBetweenJetsams;
        if (timeBetweenJetsams != nil) {
            NSLog(@"TimeBetweenJetsams - (v%@) count: %d, min: %f, max: %f, stdev: %f, bins: %@",
                  key, timeBetweenJetsams.count, timeBetweenJetsams.min, timeBetweenJetsams.max,
                  [timeBetweenJetsams stdev], timeBetweenJetsams.talliedBins);
        }
    }
}

@end
