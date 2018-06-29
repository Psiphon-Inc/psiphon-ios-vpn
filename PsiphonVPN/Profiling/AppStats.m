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

+ (mach_vm_size_t)residentSetSize:(NSError *_Nullable*_Nonnull)e {
    *e = nil;

    struct mach_task_basic_info info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(),
                                   MACH_TASK_BASIC_INFO,
                                   (task_info_t)&info,
                                   &size);
    if ( kerr == KERN_SUCCESS ) {
        return info.resident_size;
    }

    *e = [NSError errorWithDomain:AppStatsErrorDomain code:AppStatsErrorCodeKernError andLocalizedDescription:[NSString stringWithFormat:@"task_info: %s", mach_error_string(kerr)]];

    return -1;
}

// Inspired by:
// - http://www.opensource.apple.com/source/top/top-67/libtop.c
// - https://github.com/crosswalk-project/chromium-crosswalk/blob/master/base/process/process_metrics_mac.cc (libtop_update_vm_regions)
+ (size_t)privateResidentSetSize:(NSError *_Nullable*_Nonnull)e {

    size_t private_bytes = 0;
    size_t private_pages_count = 0;

    mach_port_t task = mach_task_self_;
    if (task == MACH_PORT_NULL) {
        *e = [NSError errorWithDomain:AppStatsErrorDomain code:AppStatsErrorCodeKernError andLocalizedDescription:@"mach_task_self_ returned MACH_PORT_NULL"];
        return -1;
    }

    // Scan the current task's address space and count the pages that
    // are marked as private or copy on write (COW).
    vm_size_t size = 0;
    for (vm_address_t address = VM_MIN_ADDRESS;; address += size) {
        vm_region_top_info_data_t info;
        mach_msg_type_number_t info_count = VM_REGION_TOP_INFO_COUNT;
        mach_port_t object_name;
        kern_return_t kerr = vm_region_64 (task, &address, &size, VM_REGION_TOP_INFO, (vm_region_info_t)&info, &info_count, &object_name);

        if (kerr == KERN_INVALID_ADDRESS) {
            // Done scanning: we're at the end of the address space
            break;
        } else if (kerr != KERN_SUCCESS) {
            *e = [NSError errorWithDomain:AppStatsErrorDomain code:AppStatsErrorCodeKernError andLocalizedDescription:[NSString stringWithFormat:@"vm_region: %s", mach_error_string(kerr)]];
            return -1;
        }

        mach_port_deallocate(mach_task_self(), object_name);

        // TODO:
        //   Continue if address is in the shared region and has share mode SM_PRIVATE.
        //   There seems to be no access to SHARED_REGION_BASE_{ARCH} and SHARED_REGION_SIZE_{ARCH}
        //   in the iOS SDK.

        if (info.share_mode == SM_COW && info.ref_count == 1) {
            // Treat single reference SM_COW as SM_PRIVATE
            info.share_mode = SM_PRIVATE;
        }

        switch (info.share_mode) {
            case SM_PRIVATE:
                private_pages_count += info.private_pages_resident;
                private_pages_count += info.shared_pages_resident;
                break;
            case SM_COW:
                private_pages_count += info.private_pages_resident;
                break;
            default:
                break;
        }
    }

    vm_size_t page_size;

    kern_return_t kerr = host_page_size(mach_host_self(), &page_size);
    if ( kerr != KERN_SUCCESS ) {
        *e = [NSError errorWithDomain:AppStatsErrorDomain code:AppStatsErrorCodeKernError andLocalizedDescription:[NSString stringWithFormat:@"host_page_size: %s", mach_error_string(kerr)]];
        return -1;
    }

    private_bytes = private_pages_count * page_size;

    return private_bytes;
}

@end
