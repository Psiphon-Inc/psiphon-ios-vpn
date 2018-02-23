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

#include <dispatch/object.h>
#include <dispatch/queue.h>
#include <dispatch/time.h>
#include <sys/param.h>
#include "DispatchUtils.h"

void dispatch_async_global(dispatch_block_t block) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
}

void dispatch_async_main(dispatch_block_t block) {
    dispatch_async(dispatch_get_main_queue(), block);
}

dispatch_time_t dispatch_time_since_now(int64_t interval) {
    return dispatch_time(DISPATCH_TIME_NOW, (int64_t) interval * NSEC_PER_SEC);
}

dispatch_time_t dispatch_walltime_sec(int64_t interval) {
    return dispatch_walltime(NULL, interval * NSEC_PER_SEC);
}
