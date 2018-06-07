/*
 * Copyright (c) 2017, Psiphon Inc.
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

#import <NetworkExtension/NetworkExtension.h>
#import "Notifier.h"
#import "Asserts.h"

#define SEND_TIMEOUT       10  // 10 seconds.
#define RCV_TIMEOUT         0  // 0 seconds.

#define PSIPHON_GROUP      "group.ca.psiphon.Psiphon"
#define PSIPHON_VPN_GROUP  "group.ca.psiphon.Psiphon.PsiphonVPN"

PsiFeedbackLogType const NotifierLogType = @"Notifier";

#pragma mark - ObserverTuple data class

// ObserverTuple is a tuple that holds a weak reference to a Notifier class delegate, along
// with the dispatch queue that the delegate wants to be called on.
@interface ObserverTuple : NSObject
@property (nonatomic, weak) id<NotifierObserver> observer;
@property (nonatomic, assign) dispatch_queue_t callbackQueue;
@end

@implementation ObserverTuple
@end

#pragma mark - Notifier

@implementation Notifier {
    CFStringRef remotePortName;
    CFStringRef localPortName;

    CFMessagePortRef remotePort;
    CFMessagePortRef localPort;

    // queue run off of the main thread for sending notifications.
    dispatch_queue_t sendQueue;

    NSMutableArray<ObserverTuple *> *observers;
}

// Class variables accessible by C functions.
static Notifier *sharedInstance;

CFDataRef messageCallback(CFMessagePortRef local, SInt32 messageId, CFDataRef data, void *info) {

    [PsiFeedbackLogger infoWithType:NotifierLogType message:@"received messageId (%d)", messageId];

    @synchronized(sharedInstance) {

        NSMutableIndexSet *deallocatedDelegates = [NSMutableIndexSet indexSet];

        // The contents of data will be deallocated after messageCallback exits.
        NSData *copy = [(__bridge NSData *)data copy];

        [sharedInstance->observers enumerateObjectsUsingBlock:^(ObserverTuple *obj, NSUInteger idx, BOOL *stop) {
            // If delegate has been deallocated, add its index to deallocatedDelegates to be removed later.
            if (!obj.observer) {
                [deallocatedDelegates addIndex:idx];
                return;
            }

            dispatch_async(obj.callbackQueue, ^{
                [obj.observer onMessageReceived:(NotifierMessageId)messageId withData:copy];
            });

        }];

        // Remove deallocated delegates.
        [sharedInstance->observers removeObjectsAtIndexes:deallocatedDelegates];
    };
    return NULL;
}

- (instancetype)init {

#if TARGET_IS_EXTENSION
    remotePortName = CFSTR(PSIPHON_GROUP);
    localPortName = CFSTR(PSIPHON_VPN_GROUP);
#else
    remotePortName = CFSTR(PSIPHON_VPN_GROUP);
    localPortName = CFSTR(PSIPHON_GROUP);
#endif

    localPort = CFMessagePortCreateLocal(kCFAllocatorDefault, localPortName, &messageCallback, NULL, NULL);
    if (!localPort) {
        [PsiFeedbackLogger errorWithType:NotifierLogType message:@"failed to create local Mach port"];
        abort();
    }

    CFMessagePortSetDispatchQueue(localPort, dispatch_get_main_queue());

    sendQueue = dispatch_queue_create("ca.psiphon.Psiphon.Notifier", DISPATCH_QUEUE_CONCURRENT);

    observers = [NSMutableArray arrayWithCapacity:1];

    return self;
}

- (void)dealloc {
    CFRelease(localPort);

    if (remotePort != NULL) {
        CFRelease(remotePort);
    }
}

# pragma mark - Public

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sharedInstance = [[Notifier alloc] init];
    });
    return sharedInstance;
}

- (void)registerObserver:(id <NotifierObserver>)observer callbackQueue:(dispatch_queue_t)queue {

    @synchronized (self) {

        __block BOOL alreadyObserving = FALSE;

        [observers enumerateObjectsUsingBlock:^(ObserverTuple *obj, NSUInteger idx, BOOL *stop) {
            if (obj.observer == observer) {
                (* stop) = alreadyObserving = TRUE;
            }
        }];

        if (!alreadyObserving) {
            ObserverTuple *tuple = [[ObserverTuple alloc] init];
            tuple.observer = observer;
            tuple.callbackQueue = queue;

            [observers addObject:tuple];
        }
    }
}

- (void)post:(NotifierMessageId)messageId completionHandler:(void (^)(BOOL success))completion {
    [self post:messageId withData:nil completionHandler:completion];
}

- (void)post:(NotifierMessageId)messageId withData:(NSData *_Nullable)data completionHandler:(void (^_Nonnull)(BOOL success))completion {

    // Sanity check.
#if TARGET_IS_EXTENSION
    PSIAssert(messageId >= 100 && messageId < 200);
#else
    PSIAssert(messageId >= 200 && messageId < 300);
#endif

    CFDataRef copy = (__bridge CFDataRef) [data copy];

    dispatch_async(sendQueue, ^{

        CFDataRef ignored = NULL;
        
        remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, remotePortName);
        if (remotePort == NULL) {
            // If the extension is not running (did not create it's own local message port), remotePort will be NULL.
            return;
        }

        SInt32 error = CFMessagePortSendRequest(remotePort, (SInt32)messageId, copy, SEND_TIMEOUT, RCV_TIMEOUT, NULL, &ignored);

        completion(error == kCFMessagePortSuccess);

        if (error != kCFMessagePortSuccess) {
            [PsiFeedbackLogger errorWithType:NotifierLogType message:@"failed to send messageId:%ld error:%d", (long)messageId, error];
        } else {
#if DEBUG
            [PsiFeedbackLogger infoWithType:@"Notifier<DEBUG>" message:@"success to send messagedId %ld", (long)messageId];
#endif
        }

    });
}

@end
