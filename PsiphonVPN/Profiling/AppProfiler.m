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

#import "AppProfiler.h"
#import <ReactiveObjC/RACCompoundDisposable.h>
#import <ReactiveObjC/RACDisposable.h>
#import <ReactiveObjC/RACReplaySubject.h>
#import <ReactiveObjC/RACScheduler.h>
#import <ReactiveObjC/RACSubject.h>
#import <ReactiveObjC/RACSignal+Operations.h>
#import "AppStats.h"
#import "Asserts.h"
#import "Logging.h"
#import "PsiFeedbackLogger.h"
#import "RACSignal+Operations2.h"

PsiFeedbackLogType const ExtensionMemoryProfilingLogType = @"MemoryProfiling";

@implementation AppProfiler {
    RACDisposable *disposable;
    float lastRSS;
}

- (void)startProfilingWithStartInterval:(NSTimeInterval)startInterval forNumLogs:(int)numLogsAtStartInterval andThenExponentialBackoffTo:(NSTimeInterval)endInterval withNumLogsAtEachBackOff:(int)numLogsAtEachBackOff {

#define backoffExponentOffset 2

    PSIAssert(startInterval < endInterval);

    [disposable dispose];

    disposable = [[RACSignal timerRepeating:^NSTimeInterval{
        static int index = 0;

        NSTimeInterval backoff = startInterval;

        if (index >= numLogsAtStartInterval) {
            int exp = (int)(index - numLogsAtStartInterval)/numLogsAtEachBackOff;
            backoff += pow(2, exp + backoffExponentOffset);
        }

        if (backoff >= endInterval) {
            return - 1;
        }

        index++;

        LOG_DEBUG(@"%@: backoff %dm%ds", ExtensionMemoryProfilingLogType, (int)backoff / 60 % 60, (int)backoff % 60);

        return backoff;

    }] subscribeNext:^(id  _Nullable x) {
        [self logMemoryReportIfDelta];
    } error:^(NSError * _Nullable error) {
        [PsiFeedbackLogger errorWithType:ExtensionMemoryProfilingLogType message:@"Unexpected error while profiling" object:error];
    } completed:^{
        [self startProfilingWithInterval:endInterval];
    }];
}

- (void)startProfilingWithInterval:(NSTimeInterval)interval {
    [disposable dispose];

    disposable = [[RACSignal interval:interval onScheduler:RACScheduler.scheduler withLeeway:1] subscribeNext:^(NSDate * _Nullable x) {
        [self logMemoryReportIfDelta];
    }];
}

- (void)stopProfiling {
    [disposable dispose];
    disposable = nil;
}

#pragma mark - Logging

- (void)logMemoryReportIfDelta {
    NSError *e;

    float rss = (float)[AppStats privateResidentSetSize:&e] / 1000000; // in MB

    if (e) {
        [PsiFeedbackLogger errorWithType:ExtensionMemoryProfilingLogType message:@"Failed to get RSS" object:e];
    } else if ((int)(lastRSS * 100) != (int)(rss * 100)) {
        // Only log if RSS has delta greater than 0.01
        lastRSS = rss;
        NSString *msg = [NSString stringWithFormat:@"%.2fM", rss];
        [PsiFeedbackLogger infoWithType:ExtensionMemoryProfilingLogType json:@{@"rss":msg}];
    }
}

+ (void)logMemoryReportWithTag:(NSString*_Nonnull)tag {
    NSError *e;

    float rss = (float)[AppStats privateResidentSetSize:&e] / 1000000; // in MB

    if (e) {
        [PsiFeedbackLogger errorWithType:ExtensionMemoryProfilingLogType message:@"Failed to get RSS" object:e];
    } else {
        NSString *msg = [NSString stringWithFormat:@"%.2fM", rss];
        [PsiFeedbackLogger infoWithType:ExtensionMemoryProfilingLogType json:@{@"rss":msg,@"tag":tag}];
    }
}

@end
