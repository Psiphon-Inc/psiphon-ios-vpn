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

/**
 * Submits a block for asynchronous execution on default priority global dispatch queue.
 *
 * dispatch_async_global is the same as
 * <code>
 * dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block)
 * </code>
 *
 * @param block
 * The block to submit to the target dispatch queue. This function performs
 * Block_copy() and Block_release() on behalf of callers.
 * The result of passing NULL in this parameter is undefined.
 */
void dispatch_async_global(dispatch_block_t block);

/**
 * Submits a block for asynchronous execution on the default queue that is bound to the main thread..
 *
 * dispatch_async_global is the same as
 * <code>
 * dispatch_async(dispatch_get_main_queue(), block)
 * </code>
 *
 * @param block
 * The block to submit to the target dispatch queue. This function performs
 * Block_copy() and Block_release() on behalf of callers.
 * The result of passing NULL in this parameter is undefined.
 */
void dispatch_async_main(dispatch_block_t block);

/**
 * Creates a dispatch_time_t relative to current time.
 * @param interval Interval in seconds.
 * @return A new dispatch_time_t
 */
dispatch_time_t dispatch_time_since_now(int64_t interval);

/**
 * Creates a dispatch_time_t using an absolute time according to the wall clock.
 * The wall clock is based on gettimeofday.
 *
 * @param interval Interval in seconds
 * @return A new dispatch_time_t
 */
dispatch_time_t dispatch_walltime_sec(int64_t interval);
