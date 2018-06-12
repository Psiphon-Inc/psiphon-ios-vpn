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

#import <ReactiveObjC/RACScheduler.h>
#import "AsyncOperation.h"
#import "RACSignal+Operations.h"
#import "RACDisposable.h"
#import "RACCompoundDisposable.h"
#import "PsiFeedbackLogger.h"
#import "NSError+Convenience.h"

PsiFeedbackLogType const AsyncOperationLogType = @"AsyncOperation";

@interface AsyncOperation ()

@property (readwrite, getter=isFinished) BOOL finished;
@property (readwrite, getter=isExecuting) BOOL executing;

@end

// Apple documentation on overriding NSOperation:
// https://developer.apple.com/documentation/foundation/nsoperation#1661262?language=objc
//
// From docs: For asynchronous (concurrent) operations following methods and properties need to be overridden:
// - start
// - asynchronous
// - executing
// - finished
//
@implementation AsyncOperation {
    OperationBlockCompletionHandler mainBlock;
}

@synthesize finished = _finished;
@synthesize executing = _executing;
@synthesize error = _error;

- (instancetype)init {
    self = [super init];
    if (self) {
        _finished = FALSE;
        _executing = FALSE;
    }
    return self;
}

- (instancetype)initWithBlock:(OperationBlockCompletionHandler)block {
    self = [self init];
    if (self) {
        mainBlock = [block copy];

        // KVO - listen to to "cancelled" value.
        [self addObserver:self forKeyPath:@"cancelled" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context {
    if ([keyPath isEqualToString:@"cancelled"]) {
        [PsiFeedbackLogger warnWithType:AsyncOperationLogType message:@"[%@] cancelled", self.name];
        self.executing = FALSE;
        self.finished = TRUE;
    }
}

// Must override since this operation is asynchronous (confusingly name concurrent in Apple documentation on NSOperation)
// According to Apple documentation: https://developer.apple.com/documentation/foundation/nsoperation/1416837-start?language=objc
// the start method of super should not be called.
- (void)start {
    // Check state if this operation is already cancelled or finished.
    if (self.cancelled || self.finished) {
        return;
    }

    self.executing = TRUE;

    [self main];
}

- (void)main {
    if (mainBlock) {
        mainBlock(^(NSError *error) {
            if (error) {
                [self operationError:error];
            } else {
                [self operationFinished];
            }
        });
    } else {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Method %@ should be implemented by subclasses.", NSStringFromSelector(_cmd)];
    }
}

- (BOOL)isAsynchronous {
    return YES;
}

- (BOOL)isFinished {
    @synchronized (self) {
        return _finished;
    }
}

- (void)setFinished:(BOOL)finished {
    if (_finished != finished) {
        [self willChangeValueForKey:@"isFinished"];
        @synchronized (self) {
            _finished = finished;
        }
        [self didChangeValueForKey:@"isFinished"];
    }
}

- (BOOL)isExecuting {
    @synchronized (self) {
        return _executing;
    }
}

- (void)setExecuting:(BOOL)executing {
    if (_executing != executing) {
        [self willChangeValueForKey:@"isExecuting"];
        @synchronized (self) {
            _executing = executing;
        }
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (void)operationFinished {
    self.executing = FALSE;
    self.finished = TRUE;
}

- (void)operationError:(NSError *)error {
    _error = error;
    self.executing = FALSE;
    self.finished = TRUE;
}

@end
