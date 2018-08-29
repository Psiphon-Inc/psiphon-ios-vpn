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

#import "AdControllerWrapper.h"
#import "Asserts.h"
#import <ReactiveObjC/RACSignal+Operations.h>
#import <ReactiveObjC/RACDisposable.h>
#import <ReactiveObjC/RACChannel.h>

@implementation AdControllerWrapperHelper

+ (RACSignal<NSNumber *> *)transformAdPresentationToTerminatingSignal:(RACSignal<NSNumber *> *)presentationStatus {
    return [AdControllerWrapperHelper transformAdPresentationToTerminatingSignal:presentationStatus
                                                     allowOutOfOrderRewardStatus:FALSE];
}

+ (RACSignal<NSNumber *> *)transformAdPresentationToTerminatingSignal:(RACSignal<NSNumber *> *)presentationStatus
                                          allowOutOfOrderRewardStatus:(BOOL)allowOutOfOrderRewardStatus {

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        __block BOOL emittedDidDisappear = FALSE;
        __block BOOL emittedDidRewardUser = FALSE;

        RACDisposable *disposable = [presentationStatus subscribeNext:^(NSNumber *value) {

            AdPresentation ap = (AdPresentation) [value integerValue];

            // Forward all events to the subscriber.
            [subscriber sendNext:value];

            // Complete immediately if the status is an error.
            if (adPresentationError(ap)) {
                [subscriber sendCompleted];
                return;
            }

            if (ap == AdPresentationDidDisappear) {
                emittedDidDisappear = TRUE;
            }

            if (ap == AdPresentationDidRewardUser) {
                emittedDidRewardUser = TRUE;
            }

            if (allowOutOfOrderRewardStatus) {
                if (emittedDidDisappear && emittedDidRewardUser) {
                    [subscriber sendCompleted];
                }
            } else {
                if (emittedDidDisappear) {
                    [subscriber sendCompleted];
                }
            }

        } error:^(NSError *error) {
            // presentationStatus is not expected to throw errors.
            PSIAssert(FALSE);
        } completed:^{
            // presentationStatus is not expected to complete.
            PSIAssert(FALSE);
        }];

        return disposable;
    }];
}

@end
