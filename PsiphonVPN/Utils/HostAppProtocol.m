/*
 * Copyright (c) 2021, Psiphon Inc.
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

#import "HostAppProtocol.h"
#import "DispatchUtils.h"

@interface Callback : NSObject

@property (nonatomic) int requestNumber;
@property (nonatomic, strong, nonnull) void (^handler)(NSString *response);

- (instancetype)initWithRequestNumber:(int)requestNumber handler:(void (^_Nonnull)(NSString *response))handler;

@end

@implementation Callback

- (instancetype)initWithRequestNumber:(int)requestNumber handler:(void (^_Nonnull)(NSString *response))handler {
    self = [super init];
    if (self) {
        self.requestNumber = requestNumber;
        self.handler = handler;
    }
    return self;
}

@end

# pragma mark -

@interface HostAppProtocol ()

@property (nonatomic) BOOL pendingHostAppRunningAckMessage;
@property (nonatomic) int hostAppRunningRequestNumber;
@property (nonatomic, strong) NSMutableArray<Callback *> *callbacks;

@end

@implementation HostAppProtocol

- (instancetype)init {
    self = [super init];
    if (self) {
        
        self.pendingHostAppRunningAckMessage = FALSE;
        self.hostAppRunningRequestNumber = 0;
        self.callbacks = [NSMutableArray array];
        
        [[Notifier sharedInstance] registerObserver:self
                                      callbackQueue:dispatch_get_main_queue()];
        
    }
    return self;
}

- (void)isHostAppProcessRunning:(void (^)(BOOL isProcessRunning))completionHandler {
    
    dispatch_async_main(^{
       
        int requestNumber = self.hostAppRunningRequestNumber;
        if (self.pendingHostAppRunningAckMessage == FALSE) {
            // If there are no pending requests, a new request with incremented request
            // number will be mad.e
            requestNumber += 1;
        }
        
        Callback *callback = [[Callback alloc] initWithRequestNumber:requestNumber handler:^(NSString *response) {
            
            if ([@"TRUE" isEqualToString:response]) {
                completionHandler(TRUE);
            } else if ([@"FALSE" isEqualToString:response]) {
                completionHandler(FALSE);
            } else {
                @throw [NSException exceptionWithName:@"Unknown value"
                                               reason:@"Unknown response value"
                                             userInfo:nil];
            }
            
        }];
                              
        [self.callbacks addObject:callback];
        
        
        // Guards against sending another request if one is already pending.
        if (self.pendingHostAppRunningAckMessage == TRUE) {
            return;
        }
        
        // Sends a new request.
        
        self.pendingHostAppRunningAckMessage = TRUE;
        
        self.hostAppRunningRequestNumber = requestNumber;
                
        [[Notifier sharedInstance] post:NotifierIsHostAppProcessRunning];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            
            [self hostAppRunningCompleted:FALSE forRequestNumber:requestNumber];
            
        });
        
    });
    
}

- (void)hostAppRunningCompleted:(BOOL)isRunning forRequestNumber:(int)requestNumber {
        
    self.pendingHostAppRunningAckMessage = FALSE;
    
    NSMutableArray *callbacksNotCalled = [NSMutableArray array];
    
    for (Callback *callback in self.callbacks) {
        
        if (callback.requestNumber == requestNumber) {
            
            callback.handler(isRunning ? @"TRUE" : @"FALSE");
            
        } else {
            
            [callbacksNotCalled addObject:callback];
            
        }
        
    }
    
    self.callbacks = callbacksNotCalled;
    
}

#pragma mark NotifierObserver protocol

- (void)onMessageReceived:(nonnull NotifierMessage)message {
    
    if ([NotifierHostAppProcessRunning isEqualToString:message]) {
        
        [self hostAppRunningCompleted:TRUE forRequestNumber:self.hostAppRunningRequestNumber];
        
    }
    
}

@end
