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

#import "AppStats.h"
#import "NSError+Convenience.h"
#import <mach/mach.h>

NSErrorDomain _Nonnull const AppStatsErrorDomain = @"AppStatsErrorDomain";

typedef NS_ERROR_ENUM(AppStatsErrorDomain, AppStatsErrorCode) {
    AppStatsErrorCodeUnknown = -1,

    AppStatsErrorCodeTaskInfoFailed = 1
};

@implementation AppStats

+ (vm_size_t)residentSetSize:(NSError *_Nullable*_Nonnull)e {
    *e = nil;

    struct task_basic_info info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(),
                                   TASK_BASIC_INFO,
                                   (task_info_t)&info,
                                   &size);
    if ( kerr == KERN_SUCCESS ) {
        return info.resident_size;
    }

    *e = [NSError errorWithDomain:AppStatsErrorDomain code:AppStatsErrorCodeTaskInfoFailed andLocalizedDescription:[NSString stringWithFormat:@"Error with task_info(): %s", mach_error_string(kerr)]];

    return -1;
}

@end
