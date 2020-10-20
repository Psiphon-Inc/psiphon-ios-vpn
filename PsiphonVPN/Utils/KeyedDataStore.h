/*
 * Copyright (c) 2020, Psiphon Inc.
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

typedef NSString *_Nonnull KeyedDataStoreKey;

NS_ASSUME_NONNULL_BEGIN


/// Generic datastore protocol.
@protocol KeyedDataStore

@required

/// Lookup any data stored under the provided key from the datastore.
/// @param key Key with which to query the datastore.
- (nullable id)lookup:(KeyedDataStoreKey)key;

/// Insert data under the provided key in the datastore.
/// @param object Data to be stored.
/// @param key Key under which to store the data.
/// @note should be changed to return an error when a datastore
/// implements this protocol that can return an error from a store operation.
- (void)insert:(id)object key:(KeyedDataStoreKey)key;

/// Removes object associated with the given key.
/// @param key The key whose value you want to remove.
- (void)removeObjectForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
