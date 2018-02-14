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
#import "RACSignal+Operations2.h"
#import "RACCompoundDisposable.h"

@implementation RACSignal (Operations2)

+ (RACSignal *)timer:(NSTimeInterval)delay {
    return [[RACSignal return:@(0)] delay:delay];
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

@end
