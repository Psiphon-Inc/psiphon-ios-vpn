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

#import "JetsamMetrics.h"

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const JetsamMetricsArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const JetsamMetricsArchiveVersionIntegerCoderKey = @"version.integer";
NSString *_Nonnull const MetricsDictionaryCoderKey = @"metrics.dict";

@interface JetsamMetrics ()

@property (nonatomic, strong) NSDictionary <NSString *, JetsamPerAppVersionStat *> *perVersionMetrics;
@property (nonatomic, strong) NSArray<BinRange*> *binRanges;

@end

@implementation JetsamMetrics

- (id)init {
    self = [super init];
    if (self) {
        self.perVersionMetrics = [[NSDictionary alloc] init];
    }

    return self;
}

- (instancetype)initWithBinRanges:(NSArray<BinRange*>*)binRanges {
    self = [self init];
    if (self) {
        self.binRanges = binRanges;
    }
    return self;
}

- (void)addJetsamForAppVersion:(NSString*)appVersion
                   runningTime:(NSTimeInterval)runningTime {

    NSMutableDictionary *newPerVersionMetrics = [[NSMutableDictionary alloc] initWithDictionary:self.perVersionMetrics];

    JetsamPerAppVersionStat *stat = [newPerVersionMetrics objectForKey:appVersion];
    if (stat == NULL) {
        stat = [[JetsamPerAppVersionStat alloc] init];
    }

    if (stat.runningTime == NULL) {
        stat.runningTime = [[RunningStat alloc] initWithValue:(double)runningTime
                                                    binRanges:self.binRanges];
    } else {
        [stat.runningTime addValue:(double)runningTime];
    }

    [newPerVersionMetrics setObject:stat forKey:appVersion];
    self.perVersionMetrics = newPerVersionMetrics;
}

- (void)addJetsamForAppVersion:(NSString*)appVersion
                   runningTime:(NSTimeInterval)runningTime
           timeSinceLastJetsam:(NSTimeInterval)timeSinceLastJetsam {

    NSMutableDictionary *newPerVersionMetrics = [[NSMutableDictionary alloc] initWithDictionary:self.perVersionMetrics];

    JetsamPerAppVersionStat *stat = [newPerVersionMetrics objectForKey:appVersion];
    if (stat == NULL) {
        stat = [[JetsamPerAppVersionStat alloc] init];
    }

    if (stat.runningTime == NULL) {
        stat.runningTime = [[RunningStat alloc] initWithValue:(double)runningTime
                                                    binRanges:self.binRanges];
    } else {
        [stat.runningTime addValue:(double)runningTime];
    }

    if (stat.timeBetweenJetsams == NULL) {
        stat.timeBetweenJetsams = [[RunningStat alloc] initWithValue:(double)timeSinceLastJetsam
                                                           binRanges:self.binRanges];
    } else {
        [stat.timeBetweenJetsams addValue:(double)timeSinceLastJetsam];
    }

    [newPerVersionMetrics setObject:stat forKey:appVersion];
    self.perVersionMetrics = newPerVersionMetrics;
}

#pragma mark - Equality

- (BOOL)isEqualToJetsamMetrics:(JetsamMetrics*)jetsamMetrics {
    return
        (self.perVersionMetrics == nil && jetsamMetrics.perVersionMetrics == nil) ||
        [jetsamMetrics.perVersionMetrics isEqualToDictionary:self.perVersionMetrics];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[JetsamMetrics class]]) {
        return NO;
    }

    return [self isEqualToJetsamMetrics:(JetsamMetrics*)object];
}

#pragma mark - NSCopying protocol implementation

- (id)copyWithZone:(NSZone *)zone {
    JetsamMetrics *x = [[JetsamMetrics alloc] init];

    x.perVersionMetrics = [self.perVersionMetrics copyWithZone:zone];

    return x;
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInteger:JetsamMetricsArchiveVersion1
                  forKey:JetsamMetricsArchiveVersionIntegerCoderKey];
    [coder encodeObject:self.perVersionMetrics
                 forKey:MetricsDictionaryCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.perVersionMetrics = [coder decodeObjectOfClass:[NSDictionary class]
                                           forKey:MetricsDictionaryCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementatino

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end
