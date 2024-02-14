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

/**
 * This class is used for profiling and logging app performance.
 */
@interface AppProfiler : NSObject

/**
 * Log profile every `interval` seconds.
 */
- (void)startProfilingWithInterval:(NSTimeInterval)interval API_AVAILABLE(ios(13.0));

/**
 * Start by logging profile every `startInterval` seconds for `numLogsAtStartInterval` logs.
 * Once this has completed the profiler logs `numLogsAtEachBackoff` logs at each exponentially
 * increasing period until this period has exceeded `endInterval`. Once the logging period
 * has surpassed `endInterval` the period is set to `endInterval` and logging continues indefinitely
 * until `stopProfiling` or another `startProfiling` call is made.
 */
- (void)startProfilingWithStartInterval:(NSTimeInterval)startInterval
                             forNumLogs:(int)numLogsAtStartInterval
            andThenExponentialBackoffTo:(NSTimeInterval)endInterval
               withNumLogsAtEachBackOff:(int)numLogsAtEachBackOff API_AVAILABLE(ios(13.0));

/**
 * Stop any active profiling. If no active profiling is ongoing this
 * is a noop.
 */
- (void)stopProfiling API_AVAILABLE(ios(13.0));

/**
 * Log available memory if the amount has changed since the last call to logAvailableMemoryIfDelta.
 */
- (void)logAvailableMemoryIfDelta API_AVAILABLE(ios(13.0));

/**
 * Log available memory with given tag for later indentification.
 */
+ (void)logAvailableMemoryWithTag:(NSString*_Nonnull)tag API_AVAILABLE(ios(13.0));

@end
