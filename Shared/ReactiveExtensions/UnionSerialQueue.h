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

@class RACTargetQueueScheduler;

NS_ASSUME_NONNULL_BEGIN

/**
 * Wrapper class for an NSOperationQueue and RACTargetQueueScheduler with the same
 * underlying serial dispatch queue.
 *
 * This class implements `debugDescription` method for debugging purposes.
 */
@interface UnionSerialQueue : NSObject

@property (nonatomic, readonly) NSString *label;
@property (nonatomic, readonly) dispatch_queue_t dispatchQueue;
@property (nonatomic, readonly) NSOperationQueue *operationQueue;
@property (nonatomic, readonly) RACTargetQueueScheduler *racTargetQueueScheduler;

+ (instancetype)createWithLabel:(NSString *)label;

- (NSDictionary *)feedbackInfo;

@end

NS_ASSUME_NONNULL_END
