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

typedef struct _CBucketRange {
    double lower_bound; // Inclusive lower bound
    double upper_bound; // Exclusive upper bound
} CBucketRange;

/// Make a bucket range.
/// @param lower_bound Inclusive lower bound.
/// @param upper_bound Exclusive upper bound.
NS_INLINE CBucketRange MakeCBucketRange(double lower_bound,
                                        double upper_bound) {
    assert(lower_bound <= upper_bound);
    CBucketRange r;
    r.lower_bound = lower_bound;
    r.upper_bound = upper_bound;

    return r;
}

NS_ASSUME_NONNULL_BEGIN

/// Obj-C wrapper for CBucketRange
@interface BucketRange : NSObject <NSCoding, NSSecureCoding>

+ (instancetype)bucketRangeWithRange:(CBucketRange)range;

/// Inclusive lower bound.
@property (readonly, nonatomic, assign) double lowerBound;

/// Exclusive upper bound.
@property (readonly, nonatomic, assign) double upperBound;

- (BOOL)isEqualToBucketRange:(BucketRange*)bucketRange;

@end

@interface Bucket : NSObject <NSCoding, NSSecureCoding>

@property (readonly, nonatomic, assign) int count;

@property (readonly, nonatomic) BucketRange *range;

+ (instancetype)bucketWithRange:(BucketRange*)range;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithRange:(BucketRange*)bucketRange;

/// Increment the bucket's count.
- (void)incrementCount;

/// Check if value is in the bucket's range.
/// @param x Value to check.
/// @return Returns true if the value falls within the range [bucket.range.lowerBound, bucket.range.upperBound).
- (BOOL)valueInRange:(double)x;

- (BOOL)isEqualToBucket:(Bucket*)bucket;

@end

@interface RunningBuckets : NSObject <NSCoding, NSSecureCoding>

@property (readonly, nonatomic, assign) int count;

@property (readonly, strong, nonatomic) NSArray<Bucket*> *buckets;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithBucketRanges:(NSArray<BucketRange*>*)bucketRanges;

- (void)addValue:(double)x;

- (BOOL)isEqualToRunningBuckets:(RunningBuckets*)buckets;

@end

NS_ASSUME_NONNULL_END
