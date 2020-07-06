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
#import "RunningBins.h"

@interface RunningBinsTest : XCTestCase

@end

@implementation RunningBinsTest

/// Tests multiple bins with different inclusive and exclusive boundaries.
- (void)testBoundaries {

    NSArray<BinRange*> *binRanges = @[
        [BinRange binRangeWithRange:MakeCBinRange(-DBL_MAX, -1)],
        [BinRange binRangeWithRange:MakeCBinRange(0.00, 1.00)],
        [BinRange binRangeWithRange:MakeCBinRange(0.00, 0.25)],
        [BinRange binRangeWithRange:MakeCBinRange(0.25, 0.50)],
        [BinRange binRangeWithRange:MakeCBinRange(0.50, 1.00)],
        [BinRange binRangeWithRange:MakeCBinRange(-DBL_MAX, DBL_MAX)]];

    RunningBins *bins = [[RunningBins alloc] initWithBinRanges:binRanges];

    NSArray<NSNumber*> *values = @[[NSNumber numberWithDouble:0],
                                   [NSNumber numberWithDouble:1],
                                   [NSNumber numberWithDouble:0.0001],
                                   [NSNumber numberWithDouble:0.25],
                                   [NSNumber numberWithDouble:0.50],
                                   [NSNumber numberWithDouble:0.75],
                                   [NSNumber numberWithDouble:0.999]];

    for (NSNumber *val in values) {
       [bins addValue:val.doubleValue];
    }

    XCTAssertEqual(bins.count, values.count);
    XCTAssertEqual([bins.bins objectAtIndex:0].count, 0);
    XCTAssertEqual([bins.bins objectAtIndex:1].count, 6);
    XCTAssertEqual([bins.bins objectAtIndex:2].count, 2);
    XCTAssertEqual([bins.bins objectAtIndex:3].count, 1);
    XCTAssertEqual([bins.bins objectAtIndex:4].count, 3);
    XCTAssertEqual([bins.bins objectAtIndex:5].count, 7);
}

@end
