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

#import "UnionSerialQueue.h"
#import "RACTargetQueueScheduler.h"
#import "Logging.h"

@interface UnionSerialQueue ()

@property (nonatomic, readwrite) NSString *label;
@property (nonatomic, readwrite) dispatch_queue_t dispatchQueue;
@property (nonatomic, readwrite) NSOperationQueue *operationQueue;
@property (nonatomic, readwrite) RACTargetQueueScheduler *racTargetQueueScheduler;

@end

@implementation UnionSerialQueue

+ (instancetype)createWithLabel:(NSString *)label {
    UnionSerialQueue *instance = [[UnionSerialQueue alloc] init];
    instance.label = label;


    instance.dispatchQueue = dispatch_queue_create([label UTF8String], DISPATCH_QUEUE_SERIAL);

    instance.operationQueue = [[NSOperationQueue alloc] init];
    instance.operationQueue.maxConcurrentOperationCount = 1;
    instance.operationQueue.underlyingQueue = instance.dispatchQueue;

    instance.racTargetQueueScheduler = [[RACTargetQueueScheduler alloc] initWithName:label
                                                                 targetQueue:instance.dispatchQueue];

    return instance;
}

- (NSString *)debugDescription {

    NSMutableString *lines = [NSMutableString string];

    [lines appendFormat:@"UnionSerialQueue %p OperationsCount=%lu [\n", self, (unsigned long)self.operationQueue.operationCount];

    for (NSOperation *op in self.operationQueue.operations) {
        [lines appendFormat:@"<%@ %p Name=%@ isFinished=%@ isReady=%@ isCancelled=%@ isExecuting=%@>,\n",
          NSStringFromClass([op class]),
          op,
          op.name,
          NSStringFromBOOL(op.finished),
          NSStringFromBOOL(op.ready),
          NSStringFromBOOL(op.cancelled),
          NSStringFromBOOL(op.executing)
        ];
    }

    [lines appendFormat:@"]\n"];

    return lines;
}

@end
