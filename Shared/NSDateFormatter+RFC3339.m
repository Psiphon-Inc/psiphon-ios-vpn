/*
 * Copyright (c) 2017, Psiphon Inc.
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
#import "NSDateFormatter+RFC3339.h"

@implementation NSDateFormatter (NSDateFormatterRFC3339)

+ (instancetype)createRFC3339MilliFormatter {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSSZZZZZ";
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return f;
}

+ (instancetype)createRFC3339Formatter {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'";
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return f;
}

+ (instancetype)sharedRFC3339DateFormatter {
    static NSDateFormatter *f = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        f = [NSDateFormatter createRFC3339Formatter];
    });
    return f;
}

+ (instancetype)sharedRFC3339MilliDateFormatter {
    static NSDateFormatter *f = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        f = [NSDateFormatter createRFC3339MilliFormatter];
    });
    return f;
}

@end
