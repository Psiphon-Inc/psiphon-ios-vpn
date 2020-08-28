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
 * Jetsam data
 * Persisted data used to track jetsam events in the extension.
 */

/// Time when the extension was last started.
- (NSDate*_Nullable)extensionStartTime;
- (void)setExtensionStartTimeToNow;

/// Time when the ticker last fired in the extension.
- (NSDate*_Nullable)tickerTime;
- (void)setTickerTimeToNow;

/*
 * Session Alerts persisted data.
 * These methods are not thread-safe.
 */

/// Reads persisted session alerts.
- (NSSet<NSNumber *> *)getSessionAlerts;

/// Adds a new session alert object to set of session alerts.
/// @return TRUE if the session alerts did not contain obj, and obj wad added. FALSE otherwise.
- (BOOL)addSessionAlert:(NSNumber *)alertId;

/// Removes `alertId` from session alerts.
- (void)removeSessionAlert:(NSNumber *)alertId;

/// Removes all persisted session alerts
- (void)removeAllSessionAlerts;

@end

NS_ASSUME_NONNULL_END
