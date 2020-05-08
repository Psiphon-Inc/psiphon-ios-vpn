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

#import "RunningMinMax.h"
#import "NSError+Convenience.h"
#include <limits.h>

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const RunningMinMaxArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const RunningMinMaxArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const MinDoubleCoderKey = @"min.dbl";
NSString *_Nonnull const MaxDoubleCoderKey = @"max.dbl";

@interface RunningMinMax ()

@property (nonatomic, assign) double min;
@property (nonatomic, assign) double max;

@end


@implementation RunningMinMax

- (instancetype)initWithMin:(double)min andMax:(double)max {
    self = [super init];
    if (self) {
        self.min = min;
        self.max = max;
    }
    return self;
}

- (instancetype)initWithValue:(double)x {
    self = [super init];
    if (self) {
        self.min = x;
        self.max = x;
    }
    return self;
}

- (void)addValue:(double)x {

    if (x > self.max) {
       self.max = x;
    } else if (x < self.min) {
       self.min = x;
    }

    return;
}

#pragma mark - Equality

- (BOOL)isEqualToRunningMinMax:(RunningMinMax*)runningMinMax {
    return
        self.min == runningMinMax.min &&
        self.max == runningMinMax.max;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[RunningMinMax class]]) {
        return NO;
    }

    return [self isEqualToRunningMinMax:(RunningMinMax*)object];
}

#pragma mark - NSCopying protocol implementation

- (id)copyWithZone:(NSZone *)zone {
    RunningMinMax *x = [[RunningMinMax alloc] init];

    x.min = self.min;
    x.max = self.max;

    return x;
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:RunningMinMaxArchiveVersion1
              forKey:RunningMinMaxArchiveVersionIntCoderKey];

    [coder encodeDouble:self.min
                 forKey:MinDoubleCoderKey];
    [coder encodeDouble:self.max
                 forKey:MaxDoubleCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    double min = [coder decodeDoubleForKey:MinDoubleCoderKey];
    double max = [coder decodeDoubleForKey:MaxDoubleCoderKey];

    return [self initWithMin:min andMax:max];
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end
