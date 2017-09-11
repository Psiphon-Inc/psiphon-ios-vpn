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

#if DEBUG

// Logs a message to Apple System Log facility with log level DEBUG
#define LOG_DEBUG(format, ...) \
 NSLog((@"<DEBUG> %s [Line %d]: " format), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)

// Logs a message to Apple System Log facility with log level WARN
#define LOG_WARN(format, ...) \
 NSLog((@"<WARN> %s [Line %d]: " format), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)

// Logs a message to Apple System Log facility with log level ERROR
#define LOG_ERROR(format, ...) \
 NSLog((@"<ERROR> %s [Line %d]: " format), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)

#else

#define LOG_DEBUG(...)
#define LOG_WARN(...)
#define LOG_ERROR(...)

#endif