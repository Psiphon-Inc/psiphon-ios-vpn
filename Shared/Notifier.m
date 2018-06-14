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

#import <NetworkExtension/NetworkExtension.h>
#import "Notifier.h"
#import "Asserts.h"
#import "DispatchUtils.h"

#define PSIPHON_GROUP      @"group.ca.psiphon.Psiphon"
#define PSIPHON_VPN_GROUP  @"group.ca.psiphon.Psiphon.PsiphonVPN"

PsiFeedbackLogType const NotifierLogType = @"Notifier";

#pragma mark - NotiferMessage values

// Messages sent by the extension.
NotifierMessage const NotifierNewHomepages           = PSIPHON_VPN_GROUP @".NewHomepages";
NotifierMessage const NotifierTunnelConnected        = PSIPHON_VPN_GROUP @".TunnelConnected";
NotifierMessage const NotifierAvailableEgressRegions = PSIPHON_VPN_GROUP @".AvailableEgressRegions";
NotifierMessage const NotifierMarkedAuthorizations   = PSIPHON_VPN_GROUP @".MarkedAuthorizations";

// Messages sent by the container.
NotifierMessage const NotifierStartVPN               = PSIPHON_GROUP @".StartVPN";
NotifierMessage const NotifierForceSubscriptionCheck = PSIPHON_GROUP @".ForceSubscriptionCheck";
NotifierMessage const NotifierAppEnteredBackground   = PSIPHON_GROUP @".AppEnteredBackground";
NotifierMessage const NotifierUpdatedAuthorizations  = PSIPHON_GROUP @".UpdatedAuthorizations";

#pragma mark - ObserverTuple data class

// ObserverTuple is a tuple that holds a weak reference to a Notifier class delegate, along
// with the dispatch queue that the delegate wants to be called on.
@interface ObserverTuple : NSObject
@property (nonatomic, weak) NSValue<NotifierObserver> *observer;
@property (nonatomic, assign) dispatch_queue_t callbackQueue;
@end

@implementation ObserverTuple
@end

#pragma mark - Notifier

@implementation Notifier {
    NSMutableArray<ObserverTuple *> *observers;
}

// Class variables accessible by C functions.
static Notifier *sharedInstance;

static void cfNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
  void const *object, CFDictionaryRef userInfo) {

    NSString *key = (__bridge NSString *)name;
    Notifier *selfPtr = (__bridge Notifier *)observer;
    [selfPtr notificationCallback:key];
}

static inline void AddDarwinNotifyObserver(CFNotificationCenterRef center, const void *observer, CFStringRef key) {
    CFNotificationCenterAddObserver(center,
      observer,
      cfNotificationCallback,
      key,
      NULL, // The object to observe should be NULL;
      CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (instancetype)init {
    observers = [NSMutableArray arrayWithCapacity:1];

    // Add self to Darwin notify center for the given key.
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();

    if (!center) {
        abort();
    }

    // Notifier instances should add itself as observer for all notifications.
#if TARGET_IS_EXTENSION
    // Listens to all messages sent by the container.
    AddDarwinNotifyObserver(center, (__bridge const void *)self, (__bridge CFStringRef)NotifierStartVPN);
    AddDarwinNotifyObserver(center, (__bridge const void *)self, (__bridge CFStringRef)NotifierForceSubscriptionCheck);
    AddDarwinNotifyObserver(center, (__bridge const void *)self, (__bridge CFStringRef)NotifierAppEnteredBackground);
    AddDarwinNotifyObserver(center, (__bridge const void *)self, (__bridge CFStringRef)NotifierUpdatedAuthorizations);
#else
    // Listens to all messages sent by the extension.
    AddDarwinNotifyObserver(center, (__bridge const void *)self, (__bridge CFStringRef)NotifierNewHomepages);
    AddDarwinNotifyObserver(center, (__bridge const void *)self, (__bridge CFStringRef)NotifierTunnelConnected);
    AddDarwinNotifyObserver(center, (__bridge const void *)self, (__bridge CFStringRef)NotifierAvailableEgressRegions);
    AddDarwinNotifyObserver(center, (__bridge const void *)self, (__bridge CFStringRef)NotifierMarkedAuthorizations);
#endif

    return self;
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

- (void)post:(NotifierMessage)message {

    dispatch_async_main(^{
        CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
        if (center) {
            CFNotificationCenterPostNotification(center, (__bridge CFStringRef)message, NULL, NULL, 0);

            [PsiFeedbackLogger infoWithType:@"Notifier<DEBUG>" message:@"sent [%@]", message];
        }
    });

}

#pragma mark - Private

- (void)notificationCallback:(NSString *)message {

    [PsiFeedbackLogger infoWithType:NotifierLogType message:@"received [%@]", message];

    @synchronized (sharedInstance) {

        NSMutableIndexSet *deallocatedDelegates = [NSMutableIndexSet indexSet];

        [sharedInstance->observers enumerateObjectsUsingBlock:^(ObserverTuple *obj, NSUInteger idx, BOOL *stop) {
            // If delegate has been deallocated, add its index to deallocatedDelegates to be removed later.
            if (!obj.observer) {
                [deallocatedDelegates addIndex:idx];
                return;
            }

            dispatch_async(obj.callbackQueue, ^{
                [obj.observer onMessageReceived:(NotifierMessage)message];
            });

        }];

        // Remove deallocated delegates.
        [sharedInstance->observers removeObjectsAtIndexes:deallocatedDelegates];

    }

}

@end
