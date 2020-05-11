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

@interface BucketRange ()

@property (nonatomic, assign) double min;
@property (nonatomic, assign) BOOL minInclusive;

@property (nonatomic, assign) double max;
@property (nonatomic, assign) BOOL maxInclusive;

@end

// Used for tracking the archive schema
NSUInteger const BucketRangeArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const BucketRangeArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const BucketRangeMinDoubleCoderKey = @"min.double";
NSString *_Nonnull const BucketRangeMinInclusiveBoolCoderKey = @"min_inclusive.bool";
NSString *_Nonnull const BucketRangeMaxDoubleCoderKey = @"max.double";
NSString *_Nonnull const BucketRangeMaxInclusiveBoolCoderKey = @"max_inclusive.bool";

@implementation BucketRange

+ (instancetype)bucketRangeWithRange:(CBucketRange)range {
    BucketRange *x = [[BucketRange alloc] init];
    x.min = range.min;
    x.minInclusive = range.minInclusive;
    x.max = range.max;
    x.maxInclusive = range.maxInclusive;

    return x;
}

#pragma mark - Equality

- (BOOL)isEqualToBucketRange:(BucketRange *)bucketRange {
    return
        self.min == bucketRange.min &&
        self.minInclusive == bucketRange.minInclusive &&
        self.max == bucketRange.max &&
        self.maxInclusive == bucketRange.maxInclusive;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[BucketRange class]]) {
        return NO;
    }

    return [self isEqualToBucketRange:(BucketRange*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:BucketRangeArchiveVersion1
              forKey:BucketRangeArchiveVersionIntCoderKey];

    [coder encodeDouble:self.min
                 forKey:BucketRangeMinDoubleCoderKey];
    [coder encodeBool:self.minInclusive
               forKey:BucketRangeMinInclusiveBoolCoderKey];

    [coder encodeDouble:self.max
                 forKey:BucketRangeMaxDoubleCoderKey];
    [coder encodeBool:self.maxInclusive
               forKey:BucketRangeMaxInclusiveBoolCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.min = [coder decodeDoubleForKey:BucketRangeMinDoubleCoderKey];
        self.minInclusive = [coder decodeBoolForKey:BucketRangeMinInclusiveBoolCoderKey];

        self.max = [coder decodeDoubleForKey:BucketRangeMaxDoubleCoderKey];
        self.maxInclusive = [coder decodeBoolForKey:BucketRangeMaxInclusiveBoolCoderKey];
    }

    return self;
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end

// Used for tracking the archive schema
NSUInteger const BucketArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const BucketArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const BucketCountIntCoderKey = @"count.int";
NSString *_Nonnull const BucketBucketRangeCoderKey = @"bucket_range.bucket_range";

@interface Bucket ()

@property (nonatomic, assign) int count;
@property (nonatomic) BucketRange *range;

@end

@implementation Bucket

+ (instancetype)bucketWithRange:(BucketRange*)range {
    return [[Bucket alloc] initWithRange:range];
}

- (instancetype)initWithRange:(BucketRange*)range {
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

#pragma mark - Equality

- (BOOL)isEqualToBucket:(Bucket*)bucket {

    NSLog(@"Here");
    return
        self.count == bucket.count &&
        [self.range isEqual:bucket.range];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[Bucket class]]) {
        return NO;
    }

    return [self isEqualToBucket:(Bucket*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:BucketArchiveVersion1
              forKey:BucketArchiveVersionIntCoderKey];

    [coder encodeInt:self.count
              forKey:BucketCountIntCoderKey];
    [coder encodeObject:self.range
                 forKey:BucketBucketRangeCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.count = [coder decodeIntForKey:BucketCountIntCoderKey];
        self.range = [coder decodeObjectOfClass:[BucketRange class]
                                         forKey:BucketBucketRangeCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end

// Used for tracking the archive schema
NSUInteger const RunningBucketsArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const RunningBucketsArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const RunningBucketsCountIntCoderKey = @"count.int";
NSString *_Nonnull const RunningBucketsBucketsCoderKey = @"buckets.buckets";

@interface RunningBuckets ()

@property (nonatomic, assign) int count;

@property (nonatomic) NSArray<Bucket*> *buckets;

@end

@implementation RunningBuckets

- (instancetype)initWithBucketRanges:(NSArray<BucketRange*>*)bucketRanges {
    self = [super init];
    if (self) {
        NSMutableArray<Bucket*> *buckets = [[NSMutableArray alloc] initWithCapacity:bucketRanges.count];
        for (BucketRange *range in bucketRanges) {
            Bucket *bucket = [[Bucket alloc] initWithRange:range];
            [buckets addObject:bucket];
        }
        
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

#pragma mark - Equality

- (BOOL)isEqualToRunningBuckets:(RunningBuckets *)buckets {
    return
        self.count == buckets.count &&
        [self.buckets isEqualToArray:buckets.buckets];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[RunningBuckets class]]) {
        return NO;
    }

    return [self isEqualToRunningBuckets:(RunningBuckets*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInt:RunningBucketsArchiveVersion1
              forKey:RunningBucketsArchiveVersionIntCoderKey];

    [coder encodeInt:self.count
              forKey:RunningBucketsCountIntCoderKey];
    [coder encodeObject:self.buckets
                 forKey:RunningBucketsBucketsCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.count = [coder decodeIntForKey:RunningBucketsCountIntCoderKey];
        self.buckets = [coder decodeObjectOfClass:[NSArray class]
                                           forKey:RunningBucketsBucketsCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end
