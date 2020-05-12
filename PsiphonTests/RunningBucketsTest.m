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
#import "RunningBuckets.h"

@interface RunningBucketsTest : XCTestCase

@end

@implementation RunningBucketsTest

/// Tests multiple buckets with different inclusive and exclusive boundaries.
- (void)testBoundaries {

    NSArray<BucketRange*> *bucketRanges = @[
        [BucketRange bucketRangeWithRange:MakeCBucketRange(-DBL_MAX, -1)],
        [BucketRange bucketRangeWithRange:MakeCBucketRange(0.00, 1.00)],
        [BucketRange bucketRangeWithRange:MakeCBucketRange(0.00, 0.25)],
        [BucketRange bucketRangeWithRange:MakeCBucketRange(0.25, 0.50)],
        [BucketRange bucketRangeWithRange:MakeCBucketRange(0.50, 1.00)],
        [BucketRange bucketRangeWithRange:MakeCBucketRange(-DBL_MAX, DBL_MAX)]];

    RunningBuckets *buckets = [[RunningBuckets alloc] initWithBucketRanges:bucketRanges];

    NSArray<NSNumber*> *values = @[[NSNumber numberWithDouble:0],
                                   [NSNumber numberWithDouble:1],
                                   [NSNumber numberWithDouble:0.0001],
                                   [NSNumber numberWithDouble:0.25],
                                   [NSNumber numberWithDouble:0.50],
                                   [NSNumber numberWithDouble:0.75],
                                   [NSNumber numberWithDouble:0.999]];

    for (NSNumber *val in values) {
       [buckets addValue:val.doubleValue];
    }

    XCTAssertEqual(buckets.count, values.count);
    XCTAssertEqual([buckets.buckets objectAtIndex:0].count, 0);
    XCTAssertEqual([buckets.buckets objectAtIndex:1].count, 6);
    XCTAssertEqual([buckets.buckets objectAtIndex:2].count, 2);
    XCTAssertEqual([buckets.buckets objectAtIndex:3].count, 1);
    XCTAssertEqual([buckets.buckets objectAtIndex:4].count, 3);
    XCTAssertEqual([buckets.buckets objectAtIndex:5].count, 7);
}

@end
