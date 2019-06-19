/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "NSDate+PSIDateExtension.h"
#import "timestamp.h"
#import "Asserts.h"
#import "Nullity.h"

// 10^9
#define POW_10_9 1000000000.0

#define SECOND_PRECISION 0
#define MILLISECOND_PRECISION 3

#define TIME_ZONE_OFFSET_UTC_MINUTES 0

@implementation NSDate (PSIDateExtension)

+ (NSString *)nowRFC3339Milli {
    return [[NSDate date] RFC3339MilliString];
}

+ (NSDate *_Nullable)fromRFC3339String:(NSString *)timestamp {

    if ([Nullity isEmpty:timestamp]) {
        return nil;
    }

    timestamp_t ts;

    int result = timestamp_parse([timestamp UTF8String], [timestamp lengthOfBytesUsingEncoding:NSUTF8StringEncoding], &ts);

    if (result != 0) {
        return nil;
    }

    double milliseconds = ts.nsec / POW_10_9;
    NSTimeInterval intervalSince1970 = ts.sec + milliseconds;

    return [NSDate dateWithTimeIntervalSince1970:intervalSince1970];
}

- (NSString *)RFC3339String {
    NSTimeInterval interval = [self timeIntervalSince1970];

    double sec_integral, sec_fraction;
    sec_fraction = modf(interval, &sec_integral);

    const timestamp_t ts = {.sec = (int64_t) sec_integral,
                            .offset = TIME_ZONE_OFFSET_UTC_MINUTES};

    char buf[40];
    size_t length = timestamp_format_precision(buf, sizeof(buf), &ts, SECOND_PRECISION);

    PSIAssert(length > 0);

    return [[NSString alloc] initWithBytes:buf length:length encoding:NSUTF8StringEncoding];
}

- (NSString *)RFC3339MilliString {

    NSTimeInterval interval = [self timeIntervalSince1970];

    double sec_integral, sec_fraction;
    sec_fraction = modf(interval, &sec_integral);

    int32_t nsec = (int32_t) (sec_fraction * POW_10_9);
    
    const timestamp_t ts = {.sec = (int64_t) sec_integral, .nsec = nsec, .offset = TIME_ZONE_OFFSET_UTC_MINUTES};

    char buf[40];
    size_t length = timestamp_format_precision(buf, sizeof(buf), &ts, MILLISECOND_PRECISION);

    PSIAssert(length > 0);

    return [[NSString alloc] initWithBytes:buf length:length encoding:NSUTF8StringEncoding];
}

@end
