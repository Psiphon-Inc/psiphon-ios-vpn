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
#include <limits.h>

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const ArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const ArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const CountIntCoderKey = @"count.int";
NSString *_Nonnull const MeanDoubleCoderKey = @"mean.dbl";
NSString *_Nonnull const OldMeanDoubleCoderKey = @"old_mean.dbl";
NSString *_Nonnull const M2DoubleCoderKey = @"m2.dbl";
NSString *_Nonnull const OldM2DoubleCoderKey = @"old_m2.dbl";
NSString *_Nonnull const MinDoubleCoderKey = @"min.dbl";
NSString *_Nonnull const MaxDoubleCoderKey = @"max.dbl";

#pragma mark - NSError key

NSErrorDomain _Nonnull const RunningStatErrorDomain = @"RunningStatErrorDomain";

@interface RunningStat ()

@property (nonatomic, assign) int count;

@property (nonatomic, assign) double mean;
@property (nonatomic, assign) double old_mean;

 // Sum of squares of differences from the current mean
@property (nonatomic, assign) double m2_s;
@property (nonatomic, assign) double old_m2_s;

@property (nonatomic, assign) double min;
@property (nonatomic, assign) double max;

@end


@implementation RunningStat

- (id)init {
    self = [super init];
    if (self) {
        self.count = 0;

        self.old_mean = 0;
        self.mean = 0;
        self.old_m2_s = 0;
        self.m2_s = 0;

        self.min = 0;
        self.max = 0;
    }
    return self;
}

- (NSError*)addValue:(double)x {
    // Running variance

    self.count++;
    // Check for overflow
    if (self.count == INT_MAX || self.count <= 0) {
        return [NSError errorWithDomain:RunningStatErrorDomain
                                   code:RunningStatErrorIntegerOverflow
                andLocalizedDescription:@"count overflowed"];
    }

    if (self.count == 1) {
        self.min = x;
        self.max = x;
        self.old_mean = x;
        self.mean = x;
        self.old_m2_s = 0;
    } else {
        self.mean = self.old_mean + (x - self.old_mean)/self.count;
        self.m2_s = self.old_m2_s + (x - self.old_mean)*(x - self.mean);

        self.old_mean = self.mean;
        self.old_m2_s = self.m2_s;

        // Check for overflow.
        // Note:
        if (self.mean == INFINITY || self.mean == -INFINITY) {
            return [NSError errorWithDomain:RunningStatErrorDomain
                               code:RunningStatErrorDoubleOverflow
            andLocalizedDescription:@"mean overflowed"];
        } else if (self.m2_s == INFINITY || self.m2_s == -INFINITY) {
            return [NSError errorWithDomain:RunningStatErrorDomain
                               code:RunningStatErrorDoubleOverflow
            andLocalizedDescription:@"m2_s overflowed"];
        }

        if (x > self.max) {
           self.max = x;
        } else if (x < self.min) {
           self.min = x;
        }
    }

    return nil;
}

- (double)stdev {
    return sqrt([self variance]);
}

- (double)variance {
    return (self.count > 1) ? self.m2_s/(self.count - 1) : 0.0;
}

#pragma mark - Equality

- (BOOL)isEqualToRunningStat:(RunningStat*)stat {
    return
        self.count == stat.count &&

        self.mean == stat.mean &&
        self.old_mean == stat.old_mean &&

        self.m2_s == stat.m2_s &&
        self.old_m2_s == stat.old_m2_s &&

        self.min == stat.min &&
        self.max == stat.max;
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
    RunningStat *x = [[RunningStat alloc] init];

    x.count = self.count;

    x.old_mean = self.old_mean;
    x.mean = self.mean;
    x.m2_s = self.m2_s;
    x.old_m2_s = self.old_m2_s;

    x.min = self.min;
    x.max = self.max;

    return x;
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:ArchiveVersion1
              forKey:ArchiveVersionIntCoderKey];

    [coder encodeInt:self.count
              forKey:CountIntCoderKey];

    [coder encodeDouble:self.mean
                 forKey:MeanDoubleCoderKey];
    [coder encodeDouble:self.old_mean
                 forKey:OldMeanDoubleCoderKey];
    [coder encodeDouble:self.m2_s
                 forKey:M2DoubleCoderKey];
    [coder encodeDouble:self.old_m2_s
                 forKey:OldM2DoubleCoderKey];

    [coder encodeDouble:self.min
                 forKey:MinDoubleCoderKey];
    [coder encodeDouble:self.max
                 forKey:MaxDoubleCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.count = [coder decodeIntForKey:CountIntCoderKey];

        self.mean = [coder decodeDoubleForKey:MeanDoubleCoderKey];
        self.old_mean = [coder decodeDoubleForKey:OldMeanDoubleCoderKey];

        self.m2_s = [coder decodeDoubleForKey:M2DoubleCoderKey];
        self.old_m2_s = [coder decodeDoubleForKey:OldM2DoubleCoderKey];

        self.min = [coder decodeDoubleForKey:MinDoubleCoderKey];
        self.max = [coder decodeDoubleForKey:MaxDoubleCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementatino

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end

