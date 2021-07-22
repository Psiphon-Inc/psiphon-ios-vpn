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
#import "PsiphonConfigReader.h"
#import "PsiphonDataSharedDB.h"

NS_ASSUME_NONNULL_BEGIN

/// Thread-safety: This class performs it's wotk NSManagedObjectContext queue, and all of it's methods
/// are blocking methods.
@interface AuthorizationStore : NSObject

/// Returns Sponsor ID based on the selected authorizations (if any).
/// - Parameter sharedDB: Updates PsiphonDataSharedDB with the SponsorID value used.
/// This method performs it's work on the main-thread.
- (NSString *)getSponsorId:(PsiphonConfigSponsorIds *)psiphonConfigSponsorIds
           updatedSharedDB:(PsiphonDataSharedDB *)sharedDB;

/// Returns a new unique set of persisted authorizations, the set contains
/// at most one authorization per access type.
/// If there are no new authorization to return since last call, this method will return nil.
///
/// Returns nil if there has been no changes to authorizations since last call.
/// Returns empty set, if all teh authorizations since last call have been removed.
///
/// This method performs it's work on the main-thread.
- (NSSet<NSString *> *_Nullable)getNewAuthorizations;

/// Flags authorization that are rejected by the Psiphon server.
/// Should be called in onActiveAuthorizationIDs.
///
/// - Returns: TRUE if an apple-subscription authorization was rejected.
///
/// This method performs it's work on the main-thread.
- (BOOL)setActiveAuthorizations:(NSArray<NSString *> *)activeAuthorizationIds;

/// Returns TRUE if either a subscription or speed-boost authorization have been used.
/// This method performs it's work on the main-thread.
- (BOOL)hasActiveSubscriptionOrSpeedBoost;

/// Returns TRUE if there is a subscription authorization persisted.
/// This method performs it's work on the main-thread.
- (BOOL)hasSubscriptionAuth;

@end

NS_ASSUME_NONNULL_END
