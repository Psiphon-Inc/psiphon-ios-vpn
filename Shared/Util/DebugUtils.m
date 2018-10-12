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

#import "DebugUtils.h"
#import "AppStats.h"


@implementation DebugUtils

+ (NSTimer *)jetsamWithAllocationInterval:(NSTimeInterval)allocationInterval withNumberOfPages:(unsigned int)pageNum {
    vm_size_t pageSize = [AppStats pageSize:nil];

    NSTimer *t = [NSTimer timerWithTimeInterval:allocationInterval repeats:TRUE block:^(NSTimer *timer) {
        char * array = (char *) malloc(sizeof(char) * pageSize * pageNum);
        for (int i = 1; i <= pageNum; i++) {
            array[i * pageSize - 1] = '0';
        }
    }];

    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSDefaultRunLoopMode];

    return t;
}

@end
