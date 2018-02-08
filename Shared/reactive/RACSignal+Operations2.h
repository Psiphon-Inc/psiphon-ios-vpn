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

/**
 * This category provides convenience operation methods not found
 * in the ReactiveObjC library.
 */
@interface RACSignal (Operations2)

/**
 * Returns an observable that emits (0) after a specified delay, and then completes.
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
 * @return The source observable modified with retry logic.
 */
- (RACSignal *)retryWhen:(RACSignal *(^)(RACSignal * errors))notificationHandler;

@end