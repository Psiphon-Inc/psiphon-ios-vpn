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

@interface Notifier : NSObject

- (_Nullable instancetype)initWithAppGroupIdentifier:(NSString *)identifier;

/*!
 * @brief Sends Darwin notification with given key.
 * @param key Unique notification key.
 */
- (void)post:(NSString *)key;

/*!
 * @brief Registers provided listener with Darwin notifications
 *        for the given key.
 * @param key Unique notification key.
 * @param listener Listener to be called when a notification with given key is sent.
 */
- (void)listenForNotification:(NSString *)key listener:(void(^)(NSString *key))listener;

/*!
 * @brief Unregisters listener associated with the given notification key.
 * @param key Unique notification key.
 */
- (void)removeListenerForKey:(nonnull NSString *)key;

/*!
 * @brief All listeners registered with this Notifier
 * will be unregistered.
 */
- (void)removeAllListeners;

@end

NS_ASSUME_NONNULL_END
