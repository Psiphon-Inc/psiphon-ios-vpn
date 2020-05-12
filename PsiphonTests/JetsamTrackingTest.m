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
        [JetsamEvent jetsamEventWithAppVersion:@"1" runningTime:10 jetsamDate:[NSDate.date timeIntervalSince1970]],
        [JetsamEvent jetsamEventWithAppVersion:@"1" runningTime:100 jetsamDate:[NSDate.date timeIntervalSince1970]],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:[NSDate.date timeIntervalSince1970]],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:[NSDate.date timeIntervalSince1970]],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:[NSDate.date timeIntervalSince1970]],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:[NSDate.date timeIntervalSince1970]],
        [JetsamEvent jetsamEventWithAppVersion:@"2" runningTime:1 jetsamDate:[NSDate.date timeIntervalSince1970]]
    ];

    NSArray<BucketRange*>* bucketRanges = @[
        [BucketRange bucketRangeWithRange:MakeCBucketRange(0, TRUE, 10, FALSE)],
        [BucketRange bucketRangeWithRange:MakeCBucketRange(10, TRUE, DBL_MAX, TRUE)],
    ];

    NSMutableDictionary<NSString*, RunningStat*>* expectedMetrics = [[NSMutableDictionary alloc] init];

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

        RunningStat *stat = [expectedMetrics objectForKey:jetsam.appVersion];
        if (stat == nil) {
            stat = [[RunningStat alloc] initWithValue:jetsam.runningTime bucketRanges:bucketRanges];
        } else {
            [stat addValue:jetsam.runningTime];
        }
        [expectedMetrics setObject:stat forKey:jetsam.appVersion];
    }

    JetsamMetrics *metrics = [ContainerJetsamTracking getMetricsFromFilePath:filePath
                                                         withRotatedFilepath:olderFilePath
                                                            registryFilepath:registryFilePath
                                                               readChunkSize:32
                                                                bucketRanges:bucketRanges
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

    NSMutableDictionary<NSString*, RunningStat*>* expectedMetrics = [[NSMutableDictionary alloc] init];

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

        RunningStat *stat = [expectedMetrics objectForKey:jetsam.appVersion];
        if (stat == nil) {
            stat = [[RunningStat alloc] initWithValue:jetsam.runningTime bucketRanges:nil];
        } else {
            [stat addValue:jetsam.runningTime];
        }
        [expectedMetrics setObject:stat forKey:jetsam.appVersion];
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:filePath];
    void *garbage_bytes = (void*)malloc(sizeof(1024));
    [fh writeData:[NSData dataWithBytes:garbage_bytes length:1024]];
    free(garbage_bytes);

    JetsamMetrics *metrics = [ContainerJetsamTracking getMetricsFromFilePath:filePath
                                                         withRotatedFilepath:olderFilePath
                                                            registryFilepath:registryFilePath
                                                               readChunkSize:32
                                                                bucketRanges:nil
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

- (void)printPerVersionMetrics:(NSDictionary<NSString*, RunningStat*>*)perVersionMetrics {
    for (NSString *key in perVersionMetrics) {
        RunningStat *stat = [perVersionMetrics objectForKey:key];
        if (stat != nil) {
            NSLog(@"(v%@) count: %d, min: %f, max: %f, stdev: %f, buckets: %@",
                  key,stat.count, stat.min, stat.max, [stat stdev], stat.talliedBuckets);
        }
    }
}

@end
