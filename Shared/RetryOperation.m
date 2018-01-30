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

#define RETRY_FOREVER -1

@interface RetryOperation ()

@property (nonatomic, nonnull) void (^ onNextBlock)(void (^_Nonnull) (NSError *_Nullable error));
@property (nonatomic, nullable) void (^ onFinishedBlock)(NSError *_Nullable lastError);
@property (nonatomic) int retryCount;
@property (nonatomic) NSTimeInterval retryInterval;
@property (nonatomic) BOOL backoff;

@end

@implementation RetryOperation {
    int currentRetryCount;
    NSTimeInterval currentTimeInterval;
    BOOL isRunning;
    BOOL isCancelled;
}

#pragma mark - Public methods

+ (instancetype)retryOperationForeverEvery:(NSTimeInterval)interval
                                    onNext:(void (^_Nonnull)(void (^_Nonnull retryCallback)(NSError *_Nullable error)))onNextBlock
{
    return [RetryOperation retryOperation:RETRY_FOREVER
                                 interval:interval
                                  backoff:FALSE onNext:onNextBlock
                               onFinished:nil];
}

+ (instancetype)retryOperation:(int)retryCount
                      interval:(NSTimeInterval)interval
                       backoff:(BOOL)backoff
                        onNext:(void (^ _Nonnull)(void (^_Nonnull retryCallback)(NSError *_Nullable error)))onNextBlock
{
    return [RetryOperation retryOperation:retryCount
                                 interval:interval
                                  backoff:backoff
                                   onNext:onNextBlock
                               onFinished:nil];
}

+ (instancetype)retryOperation:(int)retryCount
                      interval:(NSTimeInterval)interval
                       backoff:(BOOL)backoff
                        onNext:(void (^ _Nonnull)(void (^_Nonnull retryCallback)(NSError *_Nullable error)))onNextBlock
                    onFinished:(void (^_Nullable)(NSError *_Nullable lastError))onFinishedBlock
{
    RetryOperation *instance = [[RetryOperation alloc] init];
    if (instance) {
        instance.onNextBlock = onNextBlock;
        instance.onFinishedBlock = onFinishedBlock;
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
        [self runOnNextBlock];
    }
}

#pragma mark - Private methods

- (void)resetState {
    currentRetryCount = 0;
    currentTimeInterval = self.retryInterval;
    isRunning = FALSE;
    isCancelled = FALSE;
}

- (void)scheduleOnNextBlock:(NSError *_Nullable)lastError {

    if (self.retryCount == RETRY_FOREVER || currentRetryCount < self.retryCount) {

        // Operation is running, and block will execute soon.
        isRunning = TRUE;

        dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, lround(currentTimeInterval * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
              [self runOnNextBlock];
          });

        // Updates counter if not running forever.
        if (self.retryCount != RETRY_FOREVER) {
            currentRetryCount += 1;
        }
        // If flag set, do exponential backoff.
        if (self.backoff) {
            currentTimeInterval *= 2;
        }

    } else if (currentRetryCount == self.retryCount) {
        // Finished retrying, calling onFinished block.
        [self scheduleOnFinishedBlock:lastError];
    }
}

// scheduleOnFinishedBlock executed the onFinished block immediately (interval time is ignored).
- (void)scheduleOnFinishedBlock:(NSError *_Nullable)lastError {
    if (self.onFinishedBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.onFinishedBlock(lastError);
            [self resetState];
        });
    } else {
        // There is no onFinishedBlock to call, just reset the state.
        [self resetState];
    }
}

- (void)runOnNextBlock {

    isRunning = TRUE;

    // Do not execute block if operation is cancelled;
    if (isCancelled) {
        [self resetState];
        return;
    }

    self.onNextBlock(^(NSError *_Nullable error) {
        // Do not schedule if operation is cancelled.
        if (isCancelled) {
            [self resetState];
            return;
        }

        if (error) {
            // There was an error, schedule the block to be executed again.
            [self scheduleOnNextBlock:error];
        } else {
            // Done, schedule onFinished block.
            [self scheduleOnFinishedBlock:nil];
        }
    });
}

@end
