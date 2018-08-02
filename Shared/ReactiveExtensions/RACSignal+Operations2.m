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

#import <ReactiveObjC/RACSignal+Operations.h>
#import <ReactiveObjC/RACSubject.h>
#import <ReactiveObjC/RACDisposable.h>
#import <ReactiveObjC/NSArray+RACSequenceAdditions.h>
#import <ReactiveObjC/RACScheduler.h>
#import "RACSignal+Operations2.h"
#import "RACCompoundDisposable.h"
#import "RACSequence.h"
#import "Asserts.h"
#import "Logging.h"
#import "AsyncOperation.h"
#import "RACTargetQueueScheduler.h"
#import "UnionSerialQueue.h"

@implementation RACSignal (Operations2)

+ (RACSignal *)defer:(id)object selectorWithErrorCallback:(SEL)aSelector {

    PSIAssert(object != nil);
    PSIAssert([object respondsToSelector:aSelector]);

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        NSMethodSignature *methodSignature = [object methodSignatureForSelector:aSelector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        invocation.target = object;
        invocation.selector = aSelector;

        void (^completionHandler)(NSError *error) = ^(NSError *error) {
            if (error) {
                [subscriber sendError:error];
                return;
            }

            [subscriber sendNext:object];
            [subscriber sendCompleted];
        };

        [invocation setArgument:&completionHandler atIndex:2];
        [invocation retainArguments];

        RACDisposable *subscriptionDisposable = [[RACScheduler currentScheduler] schedule:^{
            [invocation invoke];
        }];

        return subscriptionDisposable;
    }];
}

+ (RACSignal *)fromArray:(NSArray *)array {
    return array.rac_sequence.signal;
}

+ (RACSignal *)timer:(NSTimeInterval)delay {
    return [[RACSignal return:@(0)] delay:delay];
}

+ (RACSignal*)timerRepeating:(NSTimeInterval(^)(void))nextDelay {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> _Nonnull subscriber) {
        return [RACSignal readDelayLoop:nextDelay withSubscriber:subscriber andCompoundDisposable:nil];
    }];
}

/**
 * Helper function for `+timerRepeating:`.
 * Performs the following loop:
 * - Read next delay from provided block
 * - If provided delay < 0:
 *   - Send completed to subscriber
 * - Otherwise:
 *   - Wait for provided delay
 *   - Send next (0) to subscriber
 *   - Repeat
 */
+ (RACDisposable *)readDelayLoop:(NSTimeInterval(^)(void))nextDelay withSubscriber:(id<RACSubscriber> _Nonnull)subscriber andCompoundDisposable:(RACCompoundDisposable *)compoundDisposable {
    if (!compoundDisposable) {
        compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }

    NSTimeInterval interval = nextDelay();

    if (interval < 0) {
        [subscriber sendCompleted];
    } else {
        __block RACDisposable *d = [[RACSignal timer:interval] subscribeCompleted:^{
            [subscriber sendNext:@0];
            [RACSignal readDelayLoop:nextDelay withSubscriber:subscriber andCompoundDisposable:compoundDisposable];
            [compoundDisposable removeDisposable:d];
        }];

        [compoundDisposable addDisposable:d];
    }

    return compoundDisposable;
}

+ (RACSignal *)rangeStartFrom:(int)start count:(int)count {
    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        for (int i = start; i < (start + count); ++i) {
            [subscriber sendNext:@(i)];
        }

        [subscriber sendCompleted];
        return nil;
    }];
}

// This implementation should be as close as possible to the RxJava implementation.
// RxJava docs: http://reactivex.io/RxJava/javadoc/rx/Observable.html#retryWhen-rx.functions.Func1-
// ReactiveX docs: http://reactivex.io/documentation/operators/retry.html
//
- (RACSignal *)retryWhen:(RACSignal *(^)(RACSignal * errors))notificationHandler {
    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        // Rx terminology:
        // - Signal and observable refer to the same thing.
        // - "source observable" in this context refers to  the `self` object
        //   or the "receiver" of this message (the retryWhen message) in Objective-C terminology.
        // - "this observable" refers to the observable returned by this method.
        // - "child subscription" refers to the subscriber of 'this observable'.

        RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

        // Errors observable passed to notificationHandler.
        // These are the errors emitted by the source observable.
        RACSubject<NSError *> *errorsSignal = [RACSubject subject];

        // Re-subscription block.
        void (^resubscribe)(void) = ^{
            RACCompoundDisposable *resubscribeDisposable = [RACCompoundDisposable compoundDisposable];
            [compoundDisposable addDisposable:resubscribeDisposable];

            __weak RACDisposable *weakResubscribeDisposable = resubscribeDisposable;

            RACDisposable *sourceSubscriptionDisposable = [self
              subscribeNext:^(id x) {
                  // Emits the source value to the child subscription.
                  [subscriber sendNext:x];
              } error:^(NSError *error) {
                  @autoreleasepool {
                      // Emits the error to the errorsSignal observable.
                      [errorsSignal sendNext:error];
                      // Eagerly remove current subscription.
                      [compoundDisposable removeDisposable:weakResubscribeDisposable];
                  }
              } completed:^{
                  @autoreleasepool {
                      // Emits the completed notification to errorsSignal observable.
                      [errorsSignal sendCompleted];
                      // Eagerly remove current subscription.
                      [compoundDisposable removeDisposable:weakResubscribeDisposable];
                  }
              }];

            [resubscribeDisposable addDisposable:sourceSubscriptionDisposable];
        };

        // error emitted by the source observable are passed to the observable provided
        // as an argument to the notificationHandler.
        // If the observable returned from notificationHandler calls `sendError` or `sendCompleted` on its subscriber,
        // then `sendError` or `sendCompleted` will be called on the child subscription,
        // otherwise this observable will resubscribe to the source observable.
        RACDisposable *notificationDisposable = [notificationHandler(errorsSignal)
          subscribeNext:^(NSError *x) {
              // Resubscribes to the source observable.
              resubscribe();
          } error:^(NSError *error) {
              [compoundDisposable dispose];
              // Passes the error to the child subscription.
              [subscriber sendError:error];
          } completed:^{
              [compoundDisposable dispose];
              // Passes the completed notification to the child subscription.
              [subscriber sendCompleted];
          }];

        // Subscribes to the source observable once immediately.
        resubscribe();

        [compoundDisposable addDisposable:notificationDisposable];
        return compoundDisposable;
    }];
}

- (RACSignal *)unsafeSubscribeOnSerialQueue:(UnionSerialQueue *)serialQueue
                                   withName:(NSString *)name {

    NSAssert(serialQueue.operationQueue.underlyingQueue != nil, @"operationQueue must have underlying dispatch operationQueue set");
    NSAssert(serialQueue.operationQueue.maxConcurrentOperationCount == 1, @"operationQueue must be serial");

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        // Creates an AsyncOperation when the returned signal is subscribed to, and adds the operation to
        // the `operationQueue`, waiting to be executed.
        //
        // When `operation` gets to the head of the queue and is executed, the source signal is subscribed to
        // on the `queueScheduler` and its events are forwarded to the `subscriber` on the same `queueScheduler`.
        //
        // Once the source signal is terminated, the `operation` changes its status to "finished" and the
        // `operationQueue` is free to execute the next operations in its queue.

        RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

        AsyncOperation *operation = [[AsyncOperation alloc] initWithBlock:^(void (^completionHandler)(NSError *)) {

            // Subscribes on the provided scheduler, and adds the scheduling disposable to `compoundDisposable`.
            [compoundDisposable addDisposable:[serialQueue.racTargetQueueScheduler schedule:^{

                // Adds subscription disposable to `compoundDisposable`.
                [compoundDisposable addDisposable:[self subscribeNext:^(id x) {

                    // To prevent unbounded size increase of compoundDisposable,
                    // do not add the returned scheduling disposable to returned `compoundDisposable`.
                    // This doesn't carry a risk.
                    [serialQueue.racTargetQueueScheduler schedule:^{
                        [subscriber sendNext:x];
                    }];

                } error:^(NSError *error) {

                    completionHandler(error);

                    // There is no risk of not adding returned subscription disposable
                    // to the returned `compoundDisposable`.
                    [serialQueue.racTargetQueueScheduler schedule:^{
                       [subscriber sendError:error];
                    }];

                } completed:^{

                    completionHandler(nil);

                    // There is no risk of not adding returned subscription disposable
                    // to the returned `compoundDisposable`.
                    [serialQueue.racTargetQueueScheduler schedule:^{
                        [subscriber sendCompleted];
                    }];
                }]];

                [compoundDisposable addDisposable:[RACDisposable disposableWithBlock:^{
                    // Subscription has been disposed of, call completionHandler to remove AsyncOperation
                    // from `operationQueue`.
                    completionHandler(nil);
                }]];

            }]];
        }];

        operation.name = name;

        [serialQueue.operationQueue addOperation:operation];

        return compoundDisposable;
    }];
}

@end
