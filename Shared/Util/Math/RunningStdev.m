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

#import "RunningStdev.h"
#import "NSError+Convenience.h"
#include <limits.h>

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const RunningStdevArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const RunningStdevArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const RunningStdevCountIntCoderKey = @"count.int";
NSString *_Nonnull const RunningStdevMeanDoubleCoderKey = @"mean.dbl";
NSString *_Nonnull const RunningStdevOldMeanDoubleCoderKey = @"old_mean.dbl";
NSString *_Nonnull const RunningStdevM2DoubleCoderKey = @"m2.dbl";
NSString *_Nonnull const RunningStdevOldM2DoubleCoderKey = @"old_m2.dbl";

#pragma mark - NSError key

NSErrorDomain _Nonnull const RunningStdevErrorDomain = @"RunningStdevErrorDomain";

@interface RunningStdev ()

@property (nonatomic, assign) int count;

@property (nonatomic, assign) double mean;
@property (nonatomic, assign) double old_mean;

 // Sum of squares of differences from the current mean
@property (nonatomic, assign) double m2_s;
@property (nonatomic, assign) double old_m2_s;

@end


@implementation RunningStdev

- (instancetype)initWithValue:(double)x {
    self = [super init];
    if (self) {
        self.count = 1;

        self.old_mean = x;
        self.mean = x;
        self.old_m2_s = 0;
        self.m2_s = 0;

        [self addValue:x];
    }
    return self;
}

- (instancetype)initWithCount:(int)count
                      oldMean:(double)oldMean
                         mean:(double)mean
                       oldM2s:(double)oldM2s
                          m2s:(double)m2s {
    self = [super init];
    if (self) {
        self.count = count;

        self.old_mean = oldMean;
        self.mean = mean;

        self.old_m2_s = oldM2s;
        self.m2_s = m2s;
    }
    return self;
}

- (NSError*)addValue:(double)x {
    // Running variance

    self.count++;
    // Check for overflow
    if (self.count == INT_MAX || self.count <= 0) {
        return [NSError errorWithDomain:RunningStdevErrorDomain
                                   code:RunningStdevErrorIntegerOverflow
                andLocalizedDescription:@"count overflowed"];
    }

    self.mean = self.old_mean + (x - self.old_mean)/self.count;
    self.m2_s = self.old_m2_s + (x - self.old_mean)*(x - self.mean);

    self.old_mean = self.mean;
    self.old_m2_s = self.m2_s;

    // Check for overflow.
    if (self.mean == INFINITY || self.mean == -INFINITY) {
        return [NSError errorWithDomain:RunningStdevErrorDomain
                           code:RunningStdevErrorDoubleOverflow
        andLocalizedDescription:@"mean overflowed"];
    } else if (self.m2_s == INFINITY || self.m2_s == -INFINITY) {
        return [NSError errorWithDomain:RunningStdevErrorDomain
                           code:RunningStdevErrorDoubleOverflow
        andLocalizedDescription:@"m2_s overflowed"];
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

- (BOOL)isEqualToRunningStdev:(RunningStdev*)stat {
    return
        self.count == stat.count &&

        self.mean == stat.mean &&
        self.old_mean == stat.old_mean &&

        self.m2_s == stat.m2_s &&
        self.old_m2_s == stat.old_m2_s;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[RunningStdev class]]) {
        return NO;
    }

    return [self isEqualToRunningStdev:(RunningStdev*)object];
}

#pragma mark - NSCopying protocol implementation

- (id)copyWithZone:(NSZone *)zone {
    RunningStdev *x = [[RunningStdev alloc] initWithCount:self.count
                                                  oldMean:self.old_mean
                                                     mean:self.mean
                                                   oldM2s:self.old_m2_s
                                                      m2s:self.m2_s];
    return x;
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:RunningStdevArchiveVersion1
              forKey:RunningStdevArchiveVersionIntCoderKey];

    [coder encodeInt:self.count
              forKey:RunningStdevCountIntCoderKey];

    [coder encodeDouble:self.mean
                 forKey:RunningStdevMeanDoubleCoderKey];
    [coder encodeDouble:self.old_mean
                 forKey:RunningStdevOldMeanDoubleCoderKey];
    [coder encodeDouble:self.m2_s
                 forKey:RunningStdevM2DoubleCoderKey];
    [coder encodeDouble:self.old_m2_s
                 forKey:RunningStdevOldM2DoubleCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {

    int count = [coder decodeIntForKey:RunningStdevCountIntCoderKey];

    double mean = [coder decodeDoubleForKey:RunningStdevMeanDoubleCoderKey];
    double old_mean = [coder decodeDoubleForKey:RunningStdevOldMeanDoubleCoderKey];

    double m2_s = [coder decodeDoubleForKey:RunningStdevM2DoubleCoderKey];
    double old_m2_s = [coder decodeDoubleForKey:RunningStdevOldM2DoubleCoderKey];

    return [self initWithCount:count
                       oldMean:old_mean
                          mean:mean
                        oldM2s:old_m2_s
                           m2s:m2_s];
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end
