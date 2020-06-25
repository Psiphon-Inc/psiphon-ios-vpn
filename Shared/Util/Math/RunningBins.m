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

#import "RunningBins.h"

@interface BinRange ()

@property (nonatomic, assign) double lowerBound;
@property (nonatomic, assign) double upperBound;

@end

// Used for tracking the archive schema
NSUInteger const BinRangeArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const BinRangeArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const BinRangeLowerBoundDoubleCoderKey = @"lower_bound.double";
NSString *_Nonnull const BinRangeUpperBoundDoubleCoderKey = @"upper_bound.double";

@implementation BinRange

+ (instancetype)binRangeWithRange:(CBinRange)range {
    BinRange *x = [[BinRange alloc] init];
    x.lowerBound = range.lower_bound;
    x.upperBound = range.upper_bound;

    return x;
}

#pragma mark - Equality

- (BOOL)isEqualToBinRange:(BinRange *)binRange {
    return
        self.lowerBound == binRange.lowerBound &&
        self.upperBound == binRange.upperBound;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[BinRange class]]) {
        return NO;
    }

    return [self isEqualToBinRange:(BinRange*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:BinRangeArchiveVersion1
              forKey:BinRangeArchiveVersionIntCoderKey];

    [coder encodeDouble:self.lowerBound
                 forKey:BinRangeLowerBoundDoubleCoderKey];
    [coder encodeDouble:self.upperBound
                 forKey:BinRangeUpperBoundDoubleCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.lowerBound = [coder decodeDoubleForKey:BinRangeLowerBoundDoubleCoderKey];
        self.upperBound = [coder decodeDoubleForKey:BinRangeUpperBoundDoubleCoderKey];
    }

    return self;
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end

// Used for tracking the archive schema
NSUInteger const BinArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const BinArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const BinCountIntCoderKey = @"count.int";
NSString *_Nonnull const BinBinRangeCoderKey = @"bin_range.bin_range";

@interface Bin ()

@property (nonatomic, assign) int count;
@property (nonatomic) BinRange *range;

@end

@implementation Bin

+ (instancetype)binWithRange:(BinRange*)range {
    return [[Bin alloc] initWithRange:range];
}

- (instancetype)initWithRange:(BinRange*)range {
    assert(range.lowerBound <= range.upperBound);

    self = [super init];
    if (self) {
        self.count = 0;
        self.range = range;
    }
    return self;
}

- (void)incrementCount {
    self.count++;
}

- (BOOL)valueInRange:(double)x {
    // Lower bound is inclusive
    if (x >= self.range.lowerBound) {
        // Upper bound is exclusive
        if (x < self.range.upperBound) {
            return TRUE;
        }
        return FALSE;
    }

    return FALSE;
}

#pragma mark - Equality

- (BOOL)isEqualToBin:(Bin*)bin {

    NSLog(@"Here");
    return
        self.count == bin.count &&
        [self.range isEqual:bin.range];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[Bin class]]) {
        return NO;
    }

    return [self isEqualToBin:(Bin*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:BinArchiveVersion1
              forKey:BinArchiveVersionIntCoderKey];

    [coder encodeInt:self.count
              forKey:BinCountIntCoderKey];
    [coder encodeObject:self.range
                 forKey:BinBinRangeCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.count = [coder decodeIntForKey:BinCountIntCoderKey];
        self.range = [coder decodeObjectOfClass:[BinRange class]
                                         forKey:BinBinRangeCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end

// Used for tracking the archive schema
NSUInteger const RunningBinsArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const RunningBinsArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const RunningBinsCountIntCoderKey = @"count.int";
NSString *_Nonnull const RunningBinsBinsCoderKey = @"bins.bins";

@interface RunningBins ()

@property (nonatomic, assign) int count;

@property (nonatomic) NSArray<Bin*> *bins;

@end

@implementation RunningBins

- (instancetype)initWithBinRanges:(NSArray<BinRange*>*)binRanges {
    self = [super init];
    if (self) {
        NSMutableArray<Bin*> *bins = [[NSMutableArray alloc] initWithCapacity:binRanges.count];
        for (BinRange *range in binRanges) {
            Bin *bin = [[Bin alloc] initWithRange:range];
            [bins addObject:bin];
        }
        
        self.bins = bins;
    }
    return self;
}

- (void)addValue:(double)x {
    self.count++;
    for (Bin *bin in self.bins) {
        if ([bin valueInRange:x]) {
            [bin incrementCount];
        }
    }
}

#pragma mark - Equality

- (BOOL)isEqualToRunningBins:(RunningBins *)bins {
    return
        self.count == bins.count &&
        [self.bins isEqualToArray:bins.bins];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[RunningBins class]]) {
        return NO;
    }

    return [self isEqualToRunningBins:(RunningBins*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:RunningBinsArchiveVersion1
              forKey:RunningBinsArchiveVersionIntCoderKey];

    [coder encodeInt:self.count
              forKey:RunningBinsCountIntCoderKey];
    [coder encodeObject:self.bins
                 forKey:RunningBinsBinsCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.count = [coder decodeIntForKey:RunningBinsCountIntCoderKey];
        self.bins = [coder decodeObjectOfClass:[NSArray class]
                                        forKey:RunningBinsBinsCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end
