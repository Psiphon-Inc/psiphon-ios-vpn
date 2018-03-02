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


@interface Notifier : NSObject

- (nullable instancetype)initWithAppGroupIdentifier:(nonnull NSString *)identifier;

/*!
 * @brief Sends Darwin notification with given key.
 * @param key Unique notification key.
 */
- (void)post:(nonnull NSString *)key;

/*!
 * @brief Registers provided listener with Darwin notifications
 *        for the given key.
 * @param key Unique notification key.
 * @param listener Listener to be called when a notification with given key is sent.
 */
- (void)listenForNotification:(nonnull NSString *)key listener:(nonnull void(^)(void))listener;

/*!
 * @brief Unregisters listener associated with the given notification key.
 * @param key Unique notification key.
 */
- (void)stopListening:(nonnull NSString *)key;

/*!
 * @brief All listeners registered with this Notifier
 * will be unregistered.
 */
- (void)stopListeningForAllNotifications;

@end
