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

@interface ExtensionDataStore : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initialize the metadata store with the given datastore.
/// @param dataStore Datastore to use for storing and retrieving data.
- (instancetype)initWithDataStore:(id<KeyedDataStore>)dataStore NS_DESIGNATED_INITIALIZER;

/*
 * Subscription metadata
 */

/// ID of the last authorization obtained from the verifier server.
- (NSString*_Nullable)lastAuthID;

/// Access type of the last authorization obtained from the verifier server.
- (NSString*_Nullable)lastAuthAccessType;

/// Set new auth ID. Should be called when a new authorization is obtained from the
/// subscription verifier server.
- (void)setLastAuthID:(NSString*)lastAuthID;

/// Set new auth access type. Should be called when a new authorization is obtained
/// from the subscription verifier server.
- (void)setLastAuthAccessType:(NSString*)lastAuthAccessType;

/*
 * Jetsam data
 * Persisted data used to track jetsam events in the extension.
 */

/// Time when the extension was last started.
- (NSDate*_Nullable)extensionStartTime;
- (void)setExtensionStartTimeToNow;

/// Time when the ticker last fired in the extension.
- (NSDate*_Nullable)tickerTime;
- (void)setTickerTimeToNow;

@end

NS_ASSUME_NONNULL_END
