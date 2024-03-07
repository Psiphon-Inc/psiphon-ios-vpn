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
#import "Asserts.h"
#import "Logging.h"
#import "PsiFeedbackLogger.h"
#import <os/proc.h>

PsiFeedbackLogType const ExtensionMemoryProfilingLogType = @"MemoryProfiling";

@interface AppProfiler ()

@end

@implementation AppProfiler {
    dispatch_source_t timerDispatch;
    unsigned long long prevAvailableMemory;
}

- (void)startProfilingWithStartInterval:(NSTimeInterval)startInterval
                             forNumLogs:(int)numLogsAtStartInterval
            andThenExponentialBackoffTo:(NSTimeInterval)endInterval
               withNumLogsAtEachBackOff:(int)numLogsAtEachBackOff API_AVAILABLE(ios(13.0)) {
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
               withNumLogsAtEachBackOff:(int)numLogsAtEachBackOff index:(int)index API_AVAILABLE(ios(13.0)) {
#define backoffExponentOffset 2

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
            
            [strongSelf logAvailableMemoryIfDelta];
            
            [strongSelf startProfilingWithStartInterval:startInterval
                                             forNumLogs:numLogsAtStartInterval
                            andThenExponentialBackoffTo:endInterval
                               withNumLogsAtEachBackOff:numLogsAtEachBackOff
                                                  index:index + 1];
        }
    });
}

// Starts profiling at regular interval.
- (void)startProfilingWithInterval:(NSTimeInterval)interval API_AVAILABLE(ios(13.0)) {
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
            [strongSelf logAvailableMemoryIfDelta];
        }
    });
    
    dispatch_resume(timerDispatch);
}

- (void)stopProfiling API_AVAILABLE(ios(13.0)) {
    if (timerDispatch != nil) {
        dispatch_source_cancel(timerDispatch);
        timerDispatch = nil;
    }
}

#pragma mark - Logging

- (void)logAvailableMemoryIfDelta API_AVAILABLE(ios(13.0)) {
    unsigned long long availableMemory = (unsigned long long)os_proc_available_memory();
    if (availableMemory != self->prevAvailableMemory) {
        self->prevAvailableMemory = availableMemory;
        [AppProfiler logAvailableMemory:availableMemory withTag:@"delta"];
    }
}

+ (void)logAvailableMemoryWithTag:(NSString*_Nonnull)tag {
    [AppProfiler logAvailableMemory:os_proc_available_memory() withTag:tag];
}

+ (void)logAvailableMemory:(unsigned long long)availableMemory withTag:(NSString*_Nonnull)tag {

    // Calculate the current memory footprint of the application, which should be its memory limit
    // minus the amount of additional memory it can allocate before hitting that memory limit. I.e.,
    // memoryInUse = memoryLimit - availableMemory.
    unsigned long long memoryInUse;
    if (@available(iOS 15.0, *)) {
        // iOS 15+: network extension memory limit is 50MB; may change in a future iOS version
        memoryInUse = (50 << 20) - availableMemory;
    } else {
        // iOS 10-14: network extension memory limit is 15MB
        memoryInUse = (15 << 20) - availableMemory;
    }

    NSDictionary *json = @{
        @"Free": [AppProfiler memoryBytesInMB:availableMemory],
        @"FreeBytes": [NSNumber numberWithUnsignedLongLong:availableMemory],
        @"Used": [AppProfiler memoryBytesInMB:memoryInUse],
        @"UsedBytes": [NSNumber numberWithUnsignedLongLong:memoryInUse],
        @"Tag": tag
    };
    [PsiFeedbackLogger infoWithType:ExtensionMemoryProfilingLogType json:json];
}

# pragma mark - Helpers

+ (NSString *)memoryBytesInMB:(unsigned long long)memoryBytes {
    NSByteCountFormatter *bf = [[NSByteCountFormatter alloc] init];
    bf.allowedUnits = NSByteCountFormatterUseMB;
    bf.countStyle = NSByteCountFormatterCountStyleMemory;
    return [bf stringFromByteCount:memoryBytes];
}

@end
