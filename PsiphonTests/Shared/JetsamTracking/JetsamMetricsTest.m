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
    NSTimeInterval *samples = (NSTimeInterval*)malloc(sizeof(NSTimeInterval) * sample_size);

    for (int i = 0; i < sample_size; i++) {
        samples[i] = (double)rand()/RAND_MAX * 1000;
        [metrics addJetsamForAppVersion:appVersion
                            runningTime:samples[i]
                    timeSinceLastJetsam:samples[i]];
    }

    double actual_stdev = double_stdev(samples, sample_size);
    double actual_mean = double_mean(samples, sample_size);
    free(samples);

    JetsamPerAppVersionStat *v1Stat = [metrics.perVersionMetrics objectForKey:appVersion];
    XCTAssertNotNil(v1Stat);

    NSArray<RunningStat*> *stats = @[v1Stat.runningTime, v1Stat.timeBetweenJetsams];

    for (RunningStat *stat in stats) {

        double stat_stdev = [stat stdev];
        double stat_mean = [stat mean];

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
}

- (void)testBinRanges {
    JetsamMetrics *metrics = [[JetsamMetrics alloc] initWithBinRanges:
                              @[
                                  [BinRange binRangeWithRange:MakeCBinRange(0, 60)],
                                  [BinRange binRangeWithRange:MakeCBinRange(60, 120)]
                              ]];

    // v1
    [metrics addJetsamForAppVersion:@"1" runningTime:0 timeSinceLastJetsam:5];
    [metrics addJetsamForAppVersion:@"1" runningTime:5 timeSinceLastJetsam:10];
    [metrics addJetsamForAppVersion:@"1" runningTime:10 timeSinceLastJetsam:30];
    [metrics addJetsamForAppVersion:@"1" runningTime:60 timeSinceLastJetsam:60];
    [metrics addJetsamForAppVersion:@"1" runningTime:90 timeSinceLastJetsam:100];
    [metrics addJetsamForAppVersion:@"1" runningTime:120 timeSinceLastJetsam:110];

    // v2
    [metrics addJetsamForAppVersion:@"2" runningTime:3 timeSinceLastJetsam:10];
    [metrics addJetsamForAppVersion:@"2" runningTime:3 timeSinceLastJetsam:100];

    if (metrics.perVersionMetrics == nil) {
        XCTFail(@"Expected per version metrics");
        return;
    }

    // Check v1 metrics
    {
        JetsamPerAppVersionStat *stat = [metrics.perVersionMetrics objectForKey:@"1"];
        if (stat == nil) {
            XCTFail(@"Expected v1 stat");
            return;
        }

        NSArray<Bin*>* runningTimeBins = stat.runningTime.talliedBins;
        if (runningTimeBins == nil) {
            XCTFail(@"Expected bins");
            return;
        }

        XCTAssertEqual([runningTimeBins objectAtIndex:0].count, 3);
        XCTAssertEqual([runningTimeBins objectAtIndex:1].count, 2);

        NSArray<Bin*>* timeBetweenJetsamsBins = stat.timeBetweenJetsams.talliedBins;
        if (timeBetweenJetsamsBins == nil) {
            XCTFail(@"Expected bins");
            return;
        }
        XCTAssertEqual([timeBetweenJetsamsBins objectAtIndex:0].count, 3);
        XCTAssertEqual([timeBetweenJetsamsBins objectAtIndex:1].count, 3);
    }

    // Check v2 metrics
    {
        JetsamPerAppVersionStat *stat = [metrics.perVersionMetrics objectForKey:@"2"];
        if (stat == nil) {
            XCTFail(@"Expected v2 stat");
            return;
        }

        NSArray<Bin*>* runningTimeBins = stat.runningTime.talliedBins;
        if (runningTimeBins == nil) {
            XCTFail(@"Expected bins");
            return;
        }

        XCTAssertEqual([runningTimeBins objectAtIndex:0].count, 2);
        XCTAssertEqual([runningTimeBins objectAtIndex:1].count, 0);

        NSArray<Bin*>* timeBetweenJetsamsBins = stat.timeBetweenJetsams.talliedBins;
        if (timeBetweenJetsamsBins == nil) {
            XCTFail(@"Expected bins");
            return;
        }
        XCTAssertEqual([timeBetweenJetsamsBins objectAtIndex:0].count, 1);
        XCTAssertEqual([timeBetweenJetsamsBins objectAtIndex:1].count, 1);
    }
}

#pragma mark - NSCopying protocol implementation tests

- (void)testNSCopying {
    JetsamMetrics *metrics = [[JetsamMetrics alloc] init];
    [metrics addJetsamForAppVersion:@"1"
                        runningTime:5
                timeSinceLastJetsam:0];
    [metrics addJetsamForAppVersion:@"1"
                        runningTime:10
                timeSinceLastJetsam:60];


    JetsamMetrics *copiedMetrics = [metrics copy];
    XCTAssertNotNil(copiedMetrics);
    XCTAssertTrue([metrics isEqualToJetsamMetrics:copiedMetrics]);

    [copiedMetrics addJetsamForAppVersion:@"2"
                              runningTime:10
                      timeSinceLastJetsam:100];
    XCTAssertFalse([metrics isEqualToJetsamMetrics:copiedMetrics]);
}

#pragma mark - NSCoding protocol implementation tests

- (void)testNSCoding {
    JetsamMetrics *metrics = [[JetsamMetrics alloc] init];
    [metrics addJetsamForAppVersion:@"1"
                        runningTime:5
                timeSinceLastJetsam:0];
    [metrics addJetsamForAppVersion:@"1"
                        runningTime:10
                timeSinceLastJetsam:10];

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
