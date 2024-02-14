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
    AppStatsErrorCodeKernError = 1,
};

@implementation AppStats

+ (vm_size_t)pageSize:(NSError *_Nullable *_Nonnull)error {
    vm_size_t page_size;

    kern_return_t kerr = host_page_size(mach_host_self(), &page_size);
    if (kerr != KERN_SUCCESS) {
        if (*error) {
            *error = [NSError errorWithDomain:AppStatsErrorDomain code:AppStatsErrorCodeKernError andLocalizedDescription:[NSString stringWithFormat:@"host_page_size: %s", mach_error_string(kerr)]];
        }
        return 0;
    }

    return page_size;
}

@end
