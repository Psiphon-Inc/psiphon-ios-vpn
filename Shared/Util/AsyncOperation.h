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

typedef void (^OperationBlockCompletionHandler)(void(^completionHandler)(NSError * error));

@interface AsyncOperation : NSOperation

@property (nonatomic, readonly) NSError *error;

/**
 * completionHandler block is safe to be called more than once.
 */
- (instancetype)initWithBlock:(OperationBlockCompletionHandler)block;

@end

NS_ASSUME_NONNULL_END
