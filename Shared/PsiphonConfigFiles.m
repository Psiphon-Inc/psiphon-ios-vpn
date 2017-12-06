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

#import "PsiphonConfigFiles.h"

// File names
#define EMBEDDED_SERVER_ENTRIES @"embedded_server_entries"
#define PSIPHON_CONFIG @"psiphon_config"

@implementation PsiphonConfigFiles

+ (NSString*)embeddedServerEntriesPath {
    return [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:EMBEDDED_SERVER_ENTRIES];
}

+ (NSString*)psiphonConfigPath {
    return [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:PSIPHON_CONFIG];
}

@end
