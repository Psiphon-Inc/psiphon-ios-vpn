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

#import "RunningStat.h"
#import "NSError+Convenience.h"

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const RunningStatArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const RunningStatArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const RunningStatCountIntCoderKey = @"count.int";
NSString *_Nonnull const RunningStatMinMaxCoderKey = @"min_max.running_min_max";
NSString *_Nonnull const RunningStatStdevCoderKey = @"r_stdev.running_stdev";
NSString *_Nonnull const RunningStatBinsCoderKey = @"bins.running_bins";

#pragma mark - NSError key

NSErrorDomain _Nonnull const RunningStatErrorDomain = @"RunningStatErrorDomain";

@interface RunningStat ()

@property (nonatomic, assign) int count;

@property (nonatomic) RunningBins *bins;

@property (nonatomic) RunningMinMax *minMax;
@property (nonatomic) RunningStdev *rStdev;

@end

@implementation RunningStat

- (instancetype)initWithValue:(double)x binRanges:(NSArray<BinRange*>*)binRanges {
    self = [super init];
    if (self) {
        self.count = 1;
        self.minMax = [[RunningMinMax alloc] initWithValue:x];
        self.rStdev = [[RunningStdev alloc] initWithValue:x];
        if (binRanges != nil) {
            self.bins = [[RunningBins alloc] initWithBinRanges:binRanges];
            [self.bins addValue:x];
        }
    }
    return self;
}

- (instancetype)initWithCount:(int)count
                       minMax:(RunningMinMax*)minMax
                       rStdev:(RunningStdev*)rStdev
                         bins:(RunningBins*)bins {
    self = [super init];
    if (self) {
        self.count = count;
        self.minMax = minMax;
        self.rStdev = rStdev;
        self.bins = bins;
    }
    return self;
}

- (NSError *_Nullable)addValue:(double)x {

    self.count++;
    // Check for overflow
    if (self.count == INT_MAX || self.count <= 0) {
        return [NSError errorWithDomain:RunningStatErrorDomain
                                   code:RunningStatErrorIntegerOverflow
                andLocalizedDescription:@"count overflowed"];
    }

    if (self.bins != nil) {
        [self.bins addValue:x];
    }

    NSError *err = [self.rStdev addValue:x];
    if (err != nil) {
        return [NSError errorWithDomain:RunningStatErrorDomain
                                   code:RunningStatErrorStdev
                    withUnderlyingError:err];
    }

    [self.minMax addValue:x];

    return nil;
}

- (double)stdev {
    return [self.rStdev stdev];
}

- (double)variance {
    return [self.rStdev variance];
}

- (double)mean {
    return self.rStdev.mean;
}

- (double)min {
    return self.minMax.min;
}

- (double)max {
    return self.minMax.max;
}

- (NSArray<Bin*>*_Nullable)talliedBins {
    return self.bins.bins;
}

#pragma mark - Equality

- (BOOL)isEqualToRunningStat:(RunningStat*)stat {
    BOOL countEqual = self.count == stat.count;
    BOOL minMaxEqual = (self.minMax == nil && stat.minMax == nil) || [self.minMax isEqual:stat.minMax];
    BOOL rStdevEqual = (self.rStdev == nil && stat.rStdev == nil) || [self.rStdev isEqual:stat.rStdev];
    BOOL binsEqual = (self.bins == nil && stat.bins == nil) || [self.bins isEqual:stat.bins];

    return countEqual && minMaxEqual && rStdevEqual && binsEqual;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[RunningStat class]]) {
        return NO;
    }

    return [self isEqualToRunningStat:(RunningStat*)object];
}

#pragma mark - NSCopying protocol implementation

- (id)copyWithZone:(NSZone *)zone {
    return [[RunningStat alloc] initWithCount:self.count
                                       minMax:self.minMax
                                       rStdev:self.rStdev
                                         bins:self.bins];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:RunningStatArchiveVersion1
              forKey:RunningStatArchiveVersionIntCoderKey];

    [coder encodeInt:self.count
              forKey:RunningStatCountIntCoderKey];

    [coder encodeObject:self.minMax
                 forKey:RunningStatMinMaxCoderKey];
    [coder encodeObject:self.rStdev
                 forKey:RunningStatStdevCoderKey];

    [coder encodeObject:self.bins
                 forKey:RunningStatBinsCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {

    int count = [coder decodeIntForKey:RunningStatCountIntCoderKey];
    RunningMinMax *minMax = [coder decodeObjectOfClass:[RunningMinMax class]
                                                forKey:RunningStatMinMaxCoderKey];
    RunningStdev *rStdev = [coder decodeObjectOfClass:[RunningStdev class]
                                               forKey:RunningStatStdevCoderKey];
    RunningBins *bins = [coder decodeObjectOfClass:[RunningBins class]
                                            forKey:RunningStatBinsCoderKey];

    return [self initWithCount:count
                        minMax:minMax
                        rStdev:rStdev
                          bins:bins];
}

#pragma mark - NSSecureCoding protocol implementatino

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end
