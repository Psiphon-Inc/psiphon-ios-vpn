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
#import "RunningStat.h"
#import "Archiver.h"
#import "stats.h"

@interface RunningStatsTest : XCTestCase

@end

@implementation RunningStatsTest

// Overflows internal count integer variable.
// Note: this takes a long time to run (~5 minutes on a 2.9GHz i9).
- (void)testIntegerOverflow {
    RunningStat *stat = [[RunningStat alloc] init];
    for (int i = 0; i < INT_MAX-1; i++) {
        NSError *err = [stat addValue:1];
        if (err) {
            XCTFail(@"%@", err.localizedDescription);
            return;
        }
    }

    NSError *err = [stat addValue:1];
    XCTAssertTrue(err.code == RunningStatErrorIntegerOverflow);
}

// Overflow internal calculation.
- (void)testDoubleOverflow {
    RunningStat *stat = [[RunningStat alloc] init];
    NSError *err = [stat addValue:DBL_MAX];
    if (err != nil) {
        XCTFail(@"%@", err.localizedDescription);
        return;
    }

    err = [stat addValue:0];
    XCTAssertEqual(err.code, RunningStatErrorDoubleOverflow);
}

// Underflow internal calculation.
- (void)testDoubleUnderflow {
    RunningStat *stat = [[RunningStat alloc] init];
    NSError *err = [stat addValue:0];
    if (err != nil) {
        XCTFail(@"%@", err.localizedDescription);
        return;
    }

    err = [stat addValue:-INFINITY];
    XCTAssertEqual(err.code, RunningStatErrorDoubleOverflow);
}

- (void)testMinAndMax {
    RunningStat *stat = [[RunningStat alloc] init];

    [stat addValue:1];
    [stat addValue:-1];
    [stat addValue:4];
    [stat addValue:3];

    XCTAssertEqual(-1, stat.min);
    XCTAssertEqual(4, stat.max);
}

- (void)testStdDevAndMean {

    const double error_margin = 0.0000001;
    const unsigned int sample_size = 1000;

    RunningStat *stat = [[RunningStat alloc] init];

    srand((unsigned int)time(NULL));

    double *samples = (double*)malloc(sizeof(double)*sample_size);

    for (int i = 0; i < sample_size; i++) {
        double num = (double)rand()/RAND_MAX * 1000;
        samples[i] = num;

        // Omit the last value which is added later.
        if (i != sample_size -1 ) {
            NSError *err = [stat addValue:num];
            if (err) {
                XCTFail(@"%@", err.localizedDescription);
                return;
            }
        }
    }

    // Create a backup from which to recover from when
    // an error occurs from adding a value.
    RunningStat *statBackup = [stat copy];

    NSError *err = [stat addValue:INFINITY];
    XCTAssertNotNil(err);
    if (err) {
        XCTAssertEqual(err.code, RunningStatErrorDoubleOverflow);
    }

    // Use the backup and add the final value.
    stat = statBackup;
    [stat addValue:samples[sample_size-1]];

    double stat_stdev = [stat stdev];
    double stat_mean = stat.mean;
    double actual_stdev = double_stdev(samples, sample_size);
    double actual_mean = double_mean(samples, sample_size);
    free(samples);

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

    return;
}

#pragma mark - NSCopying protocol implementation tests

- (void)testNSCopying {
    RunningStat *stat = [[RunningStat alloc] init];
    [stat addValue:1];
    [stat addValue:5];

    RunningStat *copiedStat = [stat copy];
    XCTAssertNotNil(copiedStat);
    XCTAssertTrue([stat isEqualToRunningStat:copiedStat]);

    [copiedStat addValue:-1];
    XCTAssertFalse([stat isEqualToRunningStat:copiedStat]);
}

#pragma mark - NSCoding protocol implementation tests

- (void)testNSCoding {
    RunningStat *stat = [[RunningStat alloc] init];
    [stat addValue:1];
    [stat addValue:5];

    // Encode

    NSError *err;
    NSData *data = [Archiver archiveObject:stat error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Decode

    RunningStat *decodedStat = [Archiver unarchiveObjectWithData:data error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Compare
    XCTAssertNotNil(decodedStat);
    XCTAssertTrue([stat isEqualToRunningStat:decodedStat]);
}

@end

