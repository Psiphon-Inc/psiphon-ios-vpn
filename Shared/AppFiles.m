/*
 * Copyright (c) 2021, Psiphon Inc.
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

#import "AppFiles.h"
#import "SharedConstants.h"

@implementation AppFiles

// App Group Container shared between the host app and the Network Extension.
+ (NSURL *_Nullable)appGroupContaier {
    return [[NSFileManager defaultManager]
     containerURLForSecurityApplicationGroupIdentifier: PsiphonAppGroupIdentifier];
}

+ (NSURL *_Nullable)sharedSqliteDB {
    return [[AppFiles appGroupContaier] URLByAppendingPathComponent:@"shared_core_data.sqlite"];
}

@end
