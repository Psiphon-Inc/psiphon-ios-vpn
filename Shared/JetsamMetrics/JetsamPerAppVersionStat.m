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

#import "JetsamPerAppVersionStat.h"

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const JetsamPerAppVersionStatArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const JetsamPerAppVersionStatArchiveVersionIntegerCoderKey = @"version.integer";
NSString *_Nonnull const JetsamPerAppVersionStatRunningTimeCoderKey = @"running_time.running_stat";
NSString *_Nonnull const JetsamPerAppVersionStatTimeBetweenJetsamsCoderKey = @"time_between_jetsams.running_stat";

@implementation JetsamPerAppVersionStat

#pragma mark - Equality

- (BOOL)isEqualToJetsamPerAppVersionStat:(JetsamPerAppVersionStat*)stat{

    BOOL runningTimeEqual =
        (self.runningTime == nil && stat.runningTime == nil) ||
        [self.runningTime isEqualToRunningStat:stat.runningTime];

    BOOL timeBetweenJetsamsEqual =
        (self.timeBetweenJetsams == nil && stat.timeBetweenJetsams == nil) ||
        [self.timeBetweenJetsams isEqualToRunningStat:stat.timeBetweenJetsams];

    return runningTimeEqual && timeBetweenJetsamsEqual;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[JetsamPerAppVersionStat class]]) {
        return NO;
    }

    return [self isEqualToJetsamPerAppVersionStat:(JetsamPerAppVersionStat*)object];
}

#pragma mark - NSCopying protocol implementation

- (id)copyWithZone:(NSZone *)zone {
    JetsamPerAppVersionStat *x = [[JetsamPerAppVersionStat alloc] init];

    x.runningTime = [self.runningTime copyWithZone:zone];
    x.timeBetweenJetsams = [self.timeBetweenJetsams copyWithZone:zone];

    return x;
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInteger:JetsamPerAppVersionStatArchiveVersion1
                  forKey:JetsamPerAppVersionStatArchiveVersionIntegerCoderKey];

    [coder encodeObject:self.runningTime
                 forKey:JetsamPerAppVersionStatRunningTimeCoderKey];
    [coder encodeObject:self.timeBetweenJetsams
                 forKey:JetsamPerAppVersionStatTimeBetweenJetsamsCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.runningTime = [coder decodeObjectOfClass:[RunningStat class]
                                               forKey:JetsamPerAppVersionStatRunningTimeCoderKey];

        self.timeBetweenJetsams = [coder decodeObjectOfClass:[RunningStat class]
                                                      forKey:JetsamPerAppVersionStatTimeBetweenJetsamsCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementatino

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end
