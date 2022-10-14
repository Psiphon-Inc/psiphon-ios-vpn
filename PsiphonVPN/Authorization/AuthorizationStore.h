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
#import "Authorization.h"

NS_ASSUME_NONNULL_BEGIN

/// Thread-safety: This class is thread-safe.
@interface AuthorizationStore : NSObject

/// Returns Sponsor ID based on the selected authorizations (if any).
/// - Parameter sharedDB: Updates PsiphonDataSharedDB with the SponsorID value used.
- (NSString *)getSponsorId:(PsiphonConfigSponsorIds *)psiphonConfigSponsorIds
           updatedSharedDB:(PsiphonDataSharedDB *)sharedDB;

/// Returns a new unique set of persisted authorizations, the set contains
/// at most one authorization per access type.
/// If there are no new authorization to return since last call, this method will return nil.
///
/// Returns nil if there has been no changes to authorizations since last call.
/// Returns empty set, if all teh authorizations since last call have been removed.
- (NSSet<NSString *> *_Nullable)getNewAuthorizations;

/// Flags authorization that are rejected by the Psiphon server.
/// Should be called in onActiveAuthorizationIDs.
///
/// - Returns: Set of Authorizations that were rejected.
- (NSSet<Authorization *> *)setActiveAuthorizations:(NSArray<NSString *> *)activeAuthorizationIds;

/// Returns TRUE if either a subscription or speed-boost authorization have been used.
- (BOOL)hasActiveSubscriptionOrSpeedBoost;

/// Returns TRUE if there is a subscription authorization persisted.
- (BOOL)hasSubscriptionAuth;

@end

NS_ASSUME_NONNULL_END
