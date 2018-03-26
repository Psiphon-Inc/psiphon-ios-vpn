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
#import "RACSignal.h"

NS_ASSUME_NONNULL_BEGIN

@class RACTargetQueueScheduler;

/**
 * This category provides convenience operation methods not found
 * in the ReactiveObjC library.
 */
@interface RACSignal (Operations2)

/**
 * Returns a signal that calls provided selector on the given object when subscribed to and passes a callback block
 * to the selector's first parameter.
 *
 * Note that the selector should only have one callback parameter of type `(void (^)(NSError *error))`.
 * The signal emits an error if the callback returns an error, otherwise the signal emits the given object and completes.
 *
 * @attention The selector should should only take one parameter of type `(void (^)(NSError *error))`
 *
 * @param object The object that accepts message from the provided selector.
 * @param aSelector The message to send the provided object.
 * @return A signal whose observer's subscriptions trigger an invocation of the provided selector on the given object.
 */
+ (RACSignal *)defer:(id)object selectorWithErrorCallback:(SEL)aSelector;

/**
 * Converts an NSArray into a signal that emits the items in the array in sequence.
 *
 * @param array The source sequence
 * @return A signal that emits each item in the source NSArray.
 */
+ (RACSignal *)fromArray:(NSArray *)array;

/**
 * Returns an observable that emits (0) after a specified delay, and then completes.
 *
 * @param delay The initial delay before emitting a single 0.
 * @return An observable that emits one item after a specified delay, and then completed.
 */
+ (RACSignal *)timer:(NSTimeInterval)delay;

/**
 * Returns an observable that emits a sequence of integers within a specified range.
 * @param start The value of the first integer in the sequence.
 * @param count The number of sequential integers to generate.
 * @return An observable that emits a range of sequential integers.
 */
+ (RACSignal *)rangeStartFrom:(int)start count:(int)count;

/**
 * Returns an observable that emits the same values as the source observable (receiver object) with the
 * exception of an error. An error notification from the source will result in the emission of a NSError
 * item to the observable provided as an argument to the notificationHandler function. If that observable
 * calls `completed` or `error` then retry logic will call `completed` or `error` on the child subscription.
 * Otherwise, this observable will resubscribe to the source observable.
 *
 * @param notificationHandler Receives an observable of error notifications from the source with which
 *        a user can complete or error, aborting the retry.
 *
 * @return The source observable modified with retry logic.
 */
- (RACSignal *)retryWhen:(RACSignal *(^)(RACSignal * errors))notificationHandler;

/**
 * Asynchronously subscribes observers to this signal on the specified operation queue.
 * The operation queue is required to have underlying dispatch queue and that it must be serial.
 *
 * The operation added to `queue` is completed after the source signal has emitted one of the
 * terminal events, and then the event is forwarded to subscribers to the returned signal.
 *
 * @attention As long as the signal has not terminated (i.e. has not emitted error or completed),
 *            the `queue` will be blocked.
 *            This can cause an issue if two operations on the `queue` are dependent and both wait
 *            indefinitely for the other operation to finish.
 *
 * @param operationQueue operation queue with underlying serial dispatch queue to subscribe observers on.
 * @param queueScheduler RACTargetQueueScheduler with the same underlying dispatch queue and the `queue`.
 * @return The source observable modified so that its subscriptions happens on the specified NSOperationQueue.
 */
- (RACSignal *)unsafeSubscribeOnSerialQueue:(NSOperationQueue *)operationQueue
                                  scheduler:(RACTargetQueueScheduler *)queueScheduler;

@end

NS_ASSUME_NONNULL_END
