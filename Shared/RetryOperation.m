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

#import "RetryOperation.h"

@interface RetryOperation ()

@property (nonatomic) void (^_Nonnull block)(void (^_Nonnull) (NSError *_Nullable error));
@property (nonatomic) int retryCount;
@property (nonatomic) int retryInterval;
@property (nonatomic) BOOL backoff;

@end

@implementation RetryOperation {
    int currentRetryCount;
    int currentTimeInterval;
    BOOL isRunning;
    BOOL isCancelled;
}

#pragma mark - Public methods

+ (instancetype)retryOperationForeverEvery:(int)interval
                                     block:(void (^_Nonnull)(void (^_Nonnull retryCallback)(NSError *_Nullable error)))block {

    return [RetryOperation retryOperation:-1
                            intervalInSec:interval
                                  backoff:FALSE
                                    block:block];
}

+ (instancetype)retryOperation:(int)retryCount
                 intervalInSec:(int)interval
                       backoff:(BOOL)backoff
                         block:(void (^_Nonnull)(void (^_Nonnull retryCallback)(NSError *_Nullable error)))block {

    RetryOperation *instance = [[RetryOperation alloc] init];
    if (instance) {
        instance.block = block;
        instance.retryCount = retryCount;
        instance.retryInterval = interval;
        instance.backoff = backoff;

        [instance resetState];
    }
    return instance;
}

- (void)cancel {
    isCancelled = TRUE;
}

- (void)execute {
    // Only schedule operation if it is not already running.
    if (!isRunning) {
        [self runBlock];
    }
}

#pragma mark - Private methods

- (void)resetState {
    currentRetryCount = 0;
    currentTimeInterval = self.retryInterval;
    isRunning = FALSE;
    isCancelled = FALSE;
}

- (void)scheduleBlock {

    // Do not schedule if operation is cancelled.
    if (isCancelled) {
        [self resetState];
        return;
    }

    if (self.retryCount == -1 || currentRetryCount < self.retryCount) {

        // Operation is running, and block will execute soon.
        isRunning = TRUE;

        dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, currentTimeInterval * NSEC_PER_SEC),
          dispatch_get_main_queue(), ^{
              [self runBlock];
          });

        currentRetryCount += 1;
        // If flag set, do exponential backoff.
        if (self.backoff) {
            currentTimeInterval *= 2;
        }

    }
}

- (void)runBlock {

    isRunning = TRUE;

    // Do not execute block if operation is cancelled;
    if (isCancelled) {
        [self resetState];
        return;
    }

    self.block(^(NSError *_Nullable error) {
        if (error) {
            // There was an error, schedule the block to be executed again.
            [self scheduleBlock];
        } else {
            // Done, reset state.
            [self resetState];
        }
    });
}

@end
