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
#import "RunningMinMax.h"
#import "RunningBuckets.h"
#import "RunningStdev.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const RunningStatErrorDomain;

typedef NS_ERROR_ENUM(RunningStatErrorDomain, RunningStatErrorCode) {
    RunningStatErrorIntegerOverflow = 1,
    RunningStatErrorStdev = 2
};

/// A collection of stats computed with online algorithms
@interface RunningStat : NSObject <NSCopying, NSCoding, NSSecureCoding>

@property (readonly, nonatomic, assign) int count;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithValue:(double)x bucketRanges:(NSArray<BucketRange*>*_Nullable)bucketRanges;

- (NSError *_Nullable)addValue:(double)x;

- (double)stdev;

- (double)variance;

- (double)mean;

- (double)min;

- (double)max;

- (NSArray<Bucket*>*_Nullable)talliedBuckets;

- (BOOL)isEqualToRunningStat:(RunningStat*)stat;

@end

NS_ASSUME_NONNULL_END
