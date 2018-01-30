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

#import <Foundation/Foundation.h>


@interface RetryOperation : NSObject

/**
 * Create a RetryOperation that accepts a block to execute every *interval* seconds.
 * @param interval Time interval in seconds between the retries.
 * @param block A block to execute. If block calls retryCallback with an error, then the next execution of the block
 *        is immediately scheduled (using GCD). If the block calls retryCallback with nil the block will no longer
 *        be scheduled for execution, until the next time -execute method is called on this RetryOperation instance.
 * @return An instance of RetryOperation.
 */
+ (instancetype _Nonnull)retryOperationForeverEvery:(NSTimeInterval)interval
                                    onNext:(void (^_Nonnull)(void (^_Nonnull retryCallback)(NSError *_Nullable error)))onNextBlock;

/**
 * Convenience method, same as retryOperation:interval:backoff:onNext:onFinished: but without the onFinished block;
 * @return An instance of RetryOperation.
 */
+ (instancetype _Nonnull)retryOperation:(int)retryCount
                      interval:(NSTimeInterval)interval
                       backoff:(BOOL)backoff
                        onNext:(void (^ _Nonnull)(void (^_Nonnull retryCallback)(NSError *_Nullable error)))onNextBlock;

/**
 * Creates a RetryOperation that accepts a block to execute.
 * @param retryCount Number of times (greater or equal to 0) to retry executing the block. Pass 0 for no retries.
 * @param interval Time interval in seconds between the retries.
 * @param backoff Exponentially backoff on retries.
 * @param onNextBlock A block to execute after -execute method is called.
 *        If the block calls retryCallback with an error, then the next execution of the block
 *        is immediately scheduled (using GCD). If the block calls retryCallback with nil the block will no longer
 *        be scheduled for execution, until the next time -execute method is called on this RetryOperation instance.
 * @param onFinishedBlock An optional block, scheduled to be executed on the main thread immediately after
 *        the last time onNext block is executed.
 *        This block is always executed, unless the RetryOperation instance is cancelled.
 *        If the last call to onNext passed an error, that error will be passed to the onCompleted block.
 * @return An instance of RetryOperation.
 */
+ (instancetype _Nonnull)retryOperation:(int)retryCount
                      interval:(NSTimeInterval)interval
                       backoff:(BOOL)backoff
                        onNext:(void (^ _Nonnull)(void (^_Nonnull retryCallback)(NSError *_Nullable error)))onNextBlock
                    onFinished:(void (^_Nullable)(NSError *_Nullable lastError))onFinishedBlock;

/**
 * Cancels the next scheduled execution of the block.
 */
- (void)cancel;

/**
 * Starts executing immediately if this operation is already not running.
 * NO-OP if the operation is already running.
 */
- (void)execute;

@end
