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
@class UnionSerialQueue;

/**
 * This category provides convenience operation methods not found
 * in the ReactiveObjC library.
 */
@interface RACSignal<__covariant ValueType> (Operations2)

/**
 * emitOnly only emits `object` when subscribed to and does not terminate.
 * This has the same effect as `[[RACSignal return:object] concat:[RACSignal never]]`.
 */
+ (RACSignal *)emitOnly:(id)object;

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
 * Returns an observable that performs the following loop:
 * - Get next delay from provided block
 * - If retrieved delay < 0, complete
 * - Otherwise, emit (0) after the specified delay and repeat
 *
 * @param nextDelay Returns delay before next 0 should be emitted. Observable will complete if delay < 0.
 * @return An observable that emits one item after each delay provided. Will complete once a delay < 0 is provided.
 */
+ (RACSignal*)timerRepeating:(NSTimeInterval(^)(void))nextDelay;

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
 * Combines the emission from receiving signal with the latest emission from provided `signal`.
 * Emissions from the receiving signal are dropped as long as `signal` has not emitted any values.
 *
 * Receiving signal is the active signal, and `signal` is the passive signal.
 *
 * @note This operator subscribes to `signal` first before subscribing to the receiving signal.
 */
- (RACSignal<RACTwoTuple<ValueType, id> *> *)withLatestFrom:(RACSignal *)signal;

@end

NS_ASSUME_NONNULL_END
