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

#import "RunningBuckets.h"

@interface Bucket ()

@property (nonatomic, assign) int count;
@property (nonatomic, assign) BucketRange range;

@end

@implementation Bucket

+ (instancetype)bucketWithRange:(BucketRange)range {
    return [[Bucket alloc] initWithRange:range];
}

- (instancetype)initWithRange:(BucketRange)range {
    assert(range.min <= range.max);

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
    if (x > self.range.min || (x == self.range.min && self.range.minInclusive)) {
        if (x < self.range.max || (x == self.range.max && self.range.maxInclusive)) {
            return TRUE;
        }
        return FALSE;
    }

    return FALSE;
}

@end

@interface RunningBuckets ()

@property (nonatomic, assign) int count;

@property (nonatomic) NSArray<Bucket*> *buckets;

@end

@implementation RunningBuckets

- (instancetype)initWithBuckets:(NSArray<Bucket*>*)buckets {
    self = [super init];
    if (self) {
        self.buckets = buckets;
    }
    return self;
}

- (void)addValue:(double)x {
    self.count++;
    for (Bucket *bucket in self.buckets) {
        if ([bucket valueInRange:x]) {
            [bucket incrementCount];
        }
    }
}

@end
