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
#import "JetsamMetrics.h"
#import "Archiver.h"
#import "stats.h"

@interface JetsamMetricsTest : XCTestCase

@end

@implementation JetsamMetricsTest

- (void)testStdDevAndMean {

    const double error_margin = 0.0000001;
    NSString *_Nonnull appVersion = @"1234";

    JetsamMetrics *metrics = [[JetsamMetrics alloc] init];

    srand((unsigned int)time(NULL));

    const unsigned int sample_size = 500;
    NSTimeInterval *running_times = (NSTimeInterval*)malloc(sizeof(NSTimeInterval) * sample_size);

    for (int i = 0; i < sample_size; i++) {
        running_times[i] = (double)rand()/RAND_MAX * 1000;
        [metrics addJetsamForAppVersion:appVersion
                            runningTime:running_times[i]];
    }

    RunningStat *v1stat = [metrics.perVersionMetrics objectForKey:appVersion];
    XCTAssertNotNil(v1stat);

    double stat_stdev = [v1stat stdev];
    double stat_mean = [v1stat mean];
    double actual_stdev = double_stdev(running_times, sample_size);
    double actual_mean = double_mean(running_times, sample_size);
    free(running_times);

    double mean_diff = stat_mean - actual_mean;
    if (fabs(mean_diff) > error_margin) {
        NSString *msg = [NSString stringWithFormat:
                         @"stat_mean is off by actual_mean by more than "
                          "the set margin of error: abs(%lf - %lf) > %lf ",
                         stat_stdev,
                         actual_stdev,
                         error_margin];
        XCTFail(@"%@", msg);
    }

    double stdev_diff = stat_stdev - actual_stdev;
    if (fabs(stdev_diff) > error_margin) {
        NSString *msg = [NSString stringWithFormat:
                         @"stat_stdev is off by actual_stdev by more than "
                          "the set margin of error: abs(%lf - %lf) > %lf ",
                         stat_stdev,
                         actual_stdev,
                         error_margin];
        XCTFail(@"%@", msg);
    }
}

- (void)testBinRanges {
    JetsamMetrics *metrics = [[JetsamMetrics alloc] initWithBinRanges:
                              @[
                                  [BinRange binRangeWithRange:MakeCBinRange(0, 60)],
                                  [BinRange binRangeWithRange:MakeCBinRange(60, 120)]
                              ]];
    [metrics addJetsamForAppVersion:@"1" runningTime:0];
    [metrics addJetsamForAppVersion:@"1" runningTime:5];
    [metrics addJetsamForAppVersion:@"1" runningTime:10];
    [metrics addJetsamForAppVersion:@"1" runningTime:60];
    [metrics addJetsamForAppVersion:@"1" runningTime:90];
    [metrics addJetsamForAppVersion:@"1" runningTime:120];
    [metrics addJetsamForAppVersion:@"2" runningTime:3];
    [metrics addJetsamForAppVersion:@"2" runningTime:3];

    NSArray<Bin*>* version1Bins = [metrics.perVersionMetrics objectForKey:@"1"].talliedBins;
    if (version1Bins == nil) {
        XCTFail(@"Expected version 1 bins");
        return;
    }
    NSArray<Bin*>* version2Bins = [metrics.perVersionMetrics objectForKey:@"2"].talliedBins;
    if (version2Bins == nil) {
        XCTFail(@"Expected version 2 bins");
        return;
    }

    XCTAssertEqual([version1Bins objectAtIndex:0].count, 3);
    XCTAssertEqual([version1Bins objectAtIndex:1].count, 2);
    XCTAssertEqual([version2Bins objectAtIndex:0].count, 2);
    XCTAssertEqual([version2Bins objectAtIndex:1].count, 0);
}

#pragma mark - NSCopying protocol implementation tests

- (void)testNSCopying {
    JetsamMetrics *metrics = [[JetsamMetrics alloc] init];
    [metrics addJetsamForAppVersion:@"1"
                        runningTime:5];
    [metrics addJetsamForAppVersion:@"1"
                        runningTime:10];


    JetsamMetrics *copiedMetrics = [metrics copy];
    XCTAssertNotNil(copiedMetrics);
    XCTAssertTrue([metrics isEqualToJetsamMetrics:copiedMetrics]);

    [copiedMetrics addJetsamForAppVersion:@"2"
                              runningTime:10];
    XCTAssertFalse([metrics isEqualToJetsamMetrics:copiedMetrics]);
}

#pragma mark - NSCoding protocol implementation tests

- (void)testNSCoding {
    JetsamMetrics *metrics = [[JetsamMetrics alloc] init];
    [metrics addJetsamForAppVersion:@"1"
                        runningTime:5];
    [metrics addJetsamForAppVersion:@"1"
                        runningTime:10];

    // Encode

    NSError *err;
    NSData *data = [Archiver archiveObject:metrics error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Decode

    JetsamMetrics *decodedMetrics = [Archiver unarchiveObjectWithData:data
                                                                error:&err];

    // Compare
    XCTAssertNotNil(decodedMetrics);
    XCTAssertTrue([metrics isEqual:decodedMetrics]);
}

@end
