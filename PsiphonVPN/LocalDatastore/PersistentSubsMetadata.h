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
#import "KeyedDataStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Datastore for subscription check metadata which should be persisted.
/// With NSUserDefaults.standardUserDefaults as the backing datastore.
@interface PersistentSubsMetadataUserDefaults : NSObject

/// ID of the last authorization obtained from the verifier server.
+ (NSString*)lastAuthID;

/// Access type of the last authorization obtained from the verifier server.
+ (NSString*)lastAuthAccessType;

/// Set new auth ID. Should be called when a new authorization is obtained from the
/// subscription verifier server.
+ (void)setLastAuthID:(NSString*)lastAuthID;

/// Set new auth access type. Should be called when a new authorization is obtained
/// from the subscription verifier server.
+ (void)setLastAuthAccessType:(NSString*)lastAuthAccessType;

@end

/// Datastore for subscription check metadata which should be persisted.
/// The backing datastore is configurable in each call. A reference to the chosen
/// datastore is not held so the caller can control the memory footprint.
@interface PersistentSubsMetadata : NSObject

/// ID of the last authorization obtained from the verifier server.
+ (NSString*)lastAuthID:(id<KeyedDataStore>)dataStore;

/// Access type of the last authorization obtained from the verifier server.
+ (NSString*)lastAuthAccessType:(id<KeyedDataStore>)dataStore;

/// Set new auth ID. Should be called when a new authorization is obtained from the
/// subscription verifier server.
+ (void)setLastAuthID:(id<KeyedDataStore>)dataStore
           lastAuthID:(NSString*)lastAuthID;

/// Set new auth access type. Should be called when a new authorization is obtained
/// from the subscription verifier server.
+ (void)setLastAuthAccessType:(id<KeyedDataStore>)dataStore
               lastAccessType:(NSString*)lastAuthAccessType;

@end


NS_ASSUME_NONNULL_END
