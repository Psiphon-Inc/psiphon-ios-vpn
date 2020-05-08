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

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const RunningStdevErrorDomain;

typedef NS_ERROR_ENUM(RunningStdevErrorDomain, RunningStdevErrorCode) {
    RunningStdevErrorIntegerOverflow = 1,
    RunningStdevErrorDoubleOverflow  = 2,
};

@interface RunningStdev : NSObject <NSCopying, NSCoding, NSSecureCoding>

@property (readonly, nonatomic, assign) int count;

@property (readonly, nonatomic, assign) double mean;
@property (readonly, nonatomic, assign) double old_mean;

 // sum of squares of differences from the current mean
@property (readonly, nonatomic, assign) double m2_s;
@property (readonly, nonatomic, assign) double old_m2_s;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithValue:(double)x;

- (NSError*)addValue:(double)x;

- (double)stdev;

- (double)variance;

- (BOOL)isEqualToRunningStdev:(RunningStdev*)stat;

@end

NS_ASSUME_NONNULL_END
