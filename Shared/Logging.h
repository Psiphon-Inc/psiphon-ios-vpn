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
#import "PsiFeedbackLogger.h"

#if DEBUG

#if TARGET_IS_EXTENSION
// Logs message with PsiFeedbackLogger for debug build.
#define LOG_DEBUG(format, ...) \
 [PsiFeedbackLogger debug:(@"%s [Line %d]: " format), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__]
#else
// Logs a message to Apple System Log facility with log level DEBUG.
#define LOG_DEBUG(format, ...) \
 NSLog((@"<DEBUG> %s [Line %d]: " format), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif // TARGET_IS_EXTENSION

// Logs a message to Apple System Log facility with log level INFO.
#define LOG_INFO(format, ...) \
 NSLog((@"<INFO> %s [Line %d]: " format), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)

// Logs a message to Apple System Log facility with log level WARN.
#define LOG_WARN(format, ...) \
 NSLog((@"<WARN> %s [Line %d]: " format), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)

#else // DEBUG

#define LOG_DEBUG(...)

#define LOG_INFO(...)

#define LOG_WARN(...)

#endif // DEBUG

static inline NSString* NSStringFromBOOL(BOOL aBool) {
    return aBool? @"YES" : @"NO";
}
