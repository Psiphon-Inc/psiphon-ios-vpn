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

#import <Foundation/Foundation.h>

typedef struct _BucketRange {
    double min;
    BOOL minInclusive;
    double max;
    BOOL maxInclusive;
} BucketRange;

NS_INLINE BucketRange MakeBucketRange(double min, BOOL minInclusive,
                                      double max, BOOL maxInclusive) {
    assert(min <= max);
    BucketRange r;
    r.min = min;
    r.minInclusive = minInclusive;
    r.max = max;
    r.maxInclusive = maxInclusive;

    return r;
}

NS_ASSUME_NONNULL_BEGIN

@interface Bucket : NSObject

@property (readonly, nonatomic, assign) int count;

@property (readonly, nonatomic, assign) BucketRange range;

+ (instancetype)bucketWithRange:(BucketRange)range;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithRange:(BucketRange)bucketRange;

/// Increment the bucket's count.
- (void)incrementCount;

/// Check if value is in the bucket's range.
/// @param x Value to check.
/// @return Returns true if the value is in range, otherwise false.
- (BOOL)valueInRange:(double)x;

@end

@interface RunningBuckets : NSObject

@property (readonly, nonatomic, assign) int count;

@property (readonly, nonatomic) NSArray<Bucket*> *buckets;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithBuckets:(NSArray<Bucket*>*)buckets;

- (void)addValue:(double)x;

@end

NS_ASSUME_NONNULL_END
