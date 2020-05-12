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

@property (nonatomic, assign) double lowerBound;
@property (nonatomic, assign) double upperBound;

@end

// Used for tracking the archive schema
NSUInteger const BucketRangeArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const BucketRangeArchiveVersionIntCoderKey = @"version.int";
NSString *_Nonnull const BucketRangeLowerBoundDoubleCoderKey = @"lower_bound.double";
NSString *_Nonnull const BucketRangeUpperBoundDoubleCoderKey = @"upper_bound.double";

@implementation BucketRange

+ (instancetype)bucketRangeWithRange:(CBucketRange)range {
    BucketRange *x = [[BucketRange alloc] init];
    x.lowerBound = range.lower_bound;
    x.upperBound = range.upper_bound;

    return x;
}

#pragma mark - Equality

- (BOOL)isEqualToBucketRange:(BucketRange *)bucketRange {
    return
        self.lowerBound == bucketRange.lowerBound &&
        self.upperBound == bucketRange.upperBound;
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

    [coder encodeDouble:self.lowerBound
                 forKey:BucketRangeLowerBoundDoubleCoderKey];
    [coder encodeDouble:self.upperBound
                 forKey:BucketRangeUpperBoundDoubleCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.lowerBound = [coder decodeDoubleForKey:BucketRangeLowerBoundDoubleCoderKey];
        self.upperBound = [coder decodeDoubleForKey:BucketRangeUpperBoundDoubleCoderKey];
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
