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

@interface NSDate (Comparator)

/**
 * Before reports whether receiver's time is strictly before the given time.
 * @param time The date with which to compare the receiver.
 * @return TRUE if receiver's time is before provided time, FALSE otherwise.
 */
- (BOOL)before:(NSDate *)time;

/**
 * After reports whether receiver's time is strictly after the given time.
 * @param ttime The date with which to compare the receiver.
 * @return TRUE if receiver's time is after provided time, FALSE otherwise.
 */
- (BOOL)after:(NSDate *)time;

/**
 * Equal reports whether receiver's time is the same as the given time.
 * @param time The date with which to compare the receiver.
 * @return TRUE if receiver's time is the same as the provided time, FALSE otherwise.
 */
- (BOOL)equal:(NSDate *)time;

- (BOOL)beforeOrEqualTo:(NSDate *)time;

- (BOOL)afterOrEqualTo:(NSDate *)time;

@end
