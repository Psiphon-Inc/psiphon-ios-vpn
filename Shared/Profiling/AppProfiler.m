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
#import "AppStats.h"
#import "Asserts.h"
#import "Logging.h"
#import "PsiFeedbackLogger.h"

PsiFeedbackLogType const ExtensionMemoryProfilingLogType = @"MemoryProfiling";

@interface AppProfiler ()

@property (nonatomic, assign) BOOL suspendTimerWithBackoff;

@end

@implementation AppProfiler {
    dispatch_source_t timerDispatch;
    float lastRSS;
}

- (void)startProfilingWithStartInterval:(NSTimeInterval)startInterval
                             forNumLogs:(int)numLogsAtStartInterval
            andThenExponentialBackoffTo:(NSTimeInterval)endInterval
               withNumLogsAtEachBackOff:(int)numLogsAtEachBackOff
{
    [self startProfilingWithStartInterval:startInterval
                               forNumLogs:numLogsAtStartInterval
              andThenExponentialBackoffTo:endInterval
                 withNumLogsAtEachBackOff:numLogsAtEachBackOff
                                    index:0];
}

// Starts profiling with exponential back-off, and then with regular interval.
- (void)startProfilingWithStartInterval:(NSTimeInterval)startInterval
                             forNumLogs:(int)numLogsAtStartInterval
            andThenExponentialBackoffTo:(NSTimeInterval)endInterval
               withNumLogsAtEachBackOff:(int)numLogsAtEachBackOff index:(int)index
{
#define backoffExponentOffset 2
    
    if (self.suspendTimerWithBackoff) {
        return;
    }

    PSIAssert(startInterval < endInterval);
    
    NSTimeInterval backoff = startInterval;

    if (index >= numLogsAtStartInterval) {
        int exp = (int)(index - numLogsAtStartInterval)/numLogsAtEachBackOff;
        backoff += pow(2, exp + backoffExponentOffset);
    }

    if (backoff >= endInterval) {
        [self startProfilingWithInterval:endInterval];
        return;
    }
    
    LOG_DEBUG(@"%@: backoff %dm%ds", ExtensionMemoryProfilingLogType,
              (int)backoff / 60 % 60, (int)backoff % 60);
    
    
    AppProfiler *__weak weakSelf = self;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(backoff * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        AppProfiler *__strong strongSelf = weakSelf;
        
        if (strongSelf != nil) {
            
            [strongSelf logMemoryReportIfDelta];
            
            [strongSelf startProfilingWithStartInterval:startInterval
                                             forNumLogs:numLogsAtStartInterval
                            andThenExponentialBackoffTo:endInterval
                               withNumLogsAtEachBackOff:numLogsAtEachBackOff
                                                  index:index + 1];
        }
    });
}

// Starts profiling at regular interval.
- (void)startProfilingWithInterval:(NSTimeInterval)interval {
    AppProfiler *__weak weakSelf = self;
    
    if (timerDispatch != nil) {
        dispatch_source_cancel(timerDispatch);
    }
    
    timerDispatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                           dispatch_get_main_queue());
    
    if (timerDispatch == nil) {
        return;
    }
    
    dispatch_source_set_timer(timerDispatch,
                              dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC),
                              interval * NSEC_PER_SEC,
                              1 * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(timerDispatch, ^{
        AppProfiler *__strong strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf logMemoryReportIfDelta];
        }
    });
    
    dispatch_resume(timerDispatch);
}

- (void)stopProfiling {
    if (timerDispatch != nil) {
        dispatch_source_cancel(timerDispatch);
        timerDispatch = nil;
    }
    self.suspendTimerWithBackoff = TRUE;
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
