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

#import <Foundation/Foundation.h>
#import <notify.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NotifierMessageId) {

    // Messages sent by the extension.
    NotifierNewHomepages = 100,
    NotifierTunnelConnected = 101,
    NotifierAvailableEgressRegions = 102,

    // Messages sent by the container.
    NotifierStartVPN = 200,
    NotifierForceSubscriptionCheck = 201,
    NotifierAppEnteredBackground = 202,

};

@protocol NotifierObserver <NSObject>

@required

- (void)onMessageReceived:(NotifierMessageId)messageId withData:(NSData *)data;

@end

@interface Notifier : NSObject

+ (Notifier *)sharedInstance;

/**
 * If called from the container, posts the message to the network extension.
 * If called from the extension, posts the message to the container.
 *
 * @param completionHandler Called after the message is sent, with the success parameter set.
 *                          Errors are logged.
 */
- (void)post:(NotifierMessageId)messageId completionHandler:(void (^)(BOOL success))completion;

/**
 * Adds an observer to the Notifier.
 * Nothing happens, if the observer has already been registered.
 *
 * @param observer The observer to add to the observers' queue.
 * @param queue The dispatch queue tha the observer is called on.
 */
- (void)registerObserver:(id <NotifierObserver>)observer callbackQueue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
