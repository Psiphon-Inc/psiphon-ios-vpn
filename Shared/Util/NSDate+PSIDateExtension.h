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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSDate (PSIDateExtension)

+ (NSString *)nowRFC3339Milli;

/**
 * Create NSDate object from RFC3339 formatted timestamp.
 * @param timestamp RFC3339 formatted timestamp.
 * @return NSDate object or nil of timestamp string cannot be parsed.
 */
+ (NSDate *_Nullable)fromRFC3339String:(NSString *)timestamp;

/**
 * Formats current date with precision of 3 decimal points on the second.
 * @return RFC3339 timestamp.
 */
- (NSString *)RFC3339MilliString;

@end

NS_ASSUME_NONNULL_END
