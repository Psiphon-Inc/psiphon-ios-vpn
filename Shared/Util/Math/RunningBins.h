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

typedef struct _CBinRange {
    double lower_bound; // Inclusive lower bound
    double upper_bound; // Exclusive upper bound
} CBinRange;

/// Make a bin with a target range.
/// @param lower_bound Inclusive lower bound.
/// @param upper_bound Exclusive upper bound.
NS_INLINE CBinRange MakeCBinRange(double lower_bound,
                                        double upper_bound) {
    assert(lower_bound <= upper_bound);
    CBinRange r;
    r.lower_bound = lower_bound;
    r.upper_bound = upper_bound;

    return r;
}

NS_ASSUME_NONNULL_BEGIN

/// Obj-C wrapper for CBinRange
@interface BinRange : NSObject <NSCoding, NSSecureCoding>

+ (instancetype)binRangeWithRange:(CBinRange)range;

/// Inclusive lower bound.
@property (readonly, nonatomic, assign) double lowerBound;

/// Exclusive upper bound.
@property (readonly, nonatomic, assign) double upperBound;

- (BOOL)isEqualToBinRange:(BinRange*)binRange;

@end

@interface Bin : NSObject <NSCoding, NSSecureCoding>

@property (readonly, nonatomic, assign) int count;

@property (readonly, nonatomic) BinRange *range;

+ (instancetype)binWithRange:(BinRange*)range;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithRange:(BinRange*)binRange;

/// Increment the bin's count.
- (void)incrementCount;

/// Check if value is in the bin's range.
/// @param x Value to check.
/// @return Returns true if the value falls within the range [bin.range.lowerBound, bin.range.upperBound).
- (BOOL)valueInRange:(double)x;

- (BOOL)isEqualToBin:(Bin*)bin;

@end

@interface RunningBins : NSObject <NSCoding, NSSecureCoding>

@property (readonly, nonatomic, assign) int count;

@property (readonly, strong, nonatomic) NSArray<Bin*> *bins;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithBinRanges:(NSArray<BinRange*>*)binRanges;

- (void)addValue:(double)x;

- (BOOL)isEqualToRunningBins:(RunningBins*)bins;

@end

NS_ASSUME_NONNULL_END
