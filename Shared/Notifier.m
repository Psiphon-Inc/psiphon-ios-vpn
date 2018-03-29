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
#import "Logging.h"
#import "DispatchUtils.h"
#import "Asserts.h"

@implementation Notifier {
    NSMutableDictionary<NSString *, void(^)(NSString *)> *listeners;
    NSString *appGroupIdentifier;
}

static void cfNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
  void const *object, CFDictionaryRef userInfo) {

    NSString *key = (__bridge NSString *) name;
    Notifier *selfPtr = (__bridge Notifier *) observer;
    [selfPtr notificationCallback:key];
}

- (instancetype)initWithAppGroupIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        appGroupIdentifier = identifier;
        listeners = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterRemoveEveryObserver(center, (__bridge const void *)self);
}

# pragma mark - Public

- (void)post:(NSString *)key {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    if (center) {
        CFNotificationCenterPostNotification(center, (__bridge CFStringRef)key, NULL, NULL, YES);
    }
}

- (void)listenForNotification:(nonnull NSString *)key listener:(nonnull void(^)(NSString *))listener {
    // Assert that no listener is setup on that key already.
    PSIAssert(listeners[key] == nil);

    listeners[key] = listener;

    // Add self to Darwin notify center for the given key.
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    if (center) {
        CFNotificationCenterAddObserver(center,
          (__bridge const void *) self,
          cfNotificationCallback,
          (__bridge CFStringRef) key,
          NULL, // The object to observe should be NULL;
          CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}

- (void)removeListenerForKey:(nonnull NSString *)key {
    [listeners removeObjectForKey:key];

    // Remove self from Darwin notify center for the given key.
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    if (center) {
        CFNotificationCenterRemoveObserver(center,
          (__bridge const void *) self,
          (__bridge CFStringRef) key,
           NULL);
    }
}

- (void)removeAllListeners {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    if (center) {
        [listeners removeAllObjects];
        CFNotificationCenterRemoveEveryObserver(center, (__bridge const void *) self);
    }
}

#pragma mark - Private

- (void)notificationCallback:(NSString *)key {

    void (^listenerBlock)(NSString *) = [listeners valueForKey:key];

    if (listenerBlock) {
        dispatch_async_main(^{
            listenerBlock(key);
        });
    }

}

@end
