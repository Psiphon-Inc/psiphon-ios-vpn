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
#import "PsiphonDataSharedDB.h"
#import "PsiphonConfigReader.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ActiveAuthorizationResult) {
    
    // There are no stored authorization or there all stored authorizations are active,
    // and accepted by tunnel-core.
    ActiveAuthorizationResultNone = 0,
    
    // Subscription authorization supplied to tunnel-core is not inactive.
    ActiveAuthorizationResultInactiveSubscription = 1
};

typedef NS_ENUM(NSInteger, AuthorizationUpdateResult) {
    
    // There has been no changes to authorizations
    AuthorizationUpdateResultNoChange = 0,
    
    // There are new authorizations available, needs to reconnect
    AuthorizationUpdateResultNewAuthsAvailable = 1,
    
    // Stored authorizations have been updated, but there are no new auths
    AuthorizationUpdateResultNoNewAuths = 2
};

// SessionConfigValues represents some of the values supplied to tunnel-core in a session.
// A session is defined by when a new set of parameters are passed to tunnel-core,
// through calls to either `-getPsiphonConfig` or `-reconnectWithConfig::`.
//
// - Thread-safety: This class is not thread-safe and all of its methods should be
// called from the same dispatch queue.
@interface SessionConfigValues : NSObject

@property (nonatomic, nonnull, readonly) PsiphonConfigSponsorIds *cachedSponsorIDs;

- (instancetype _Nonnull)init NS_UNAVAILABLE;

- (instancetype)initWithSharedDB:(PsiphonDataSharedDB *)sharedDB NS_DESIGNATED_INITIALIZER;

// Checks for updated in stored authorizations relative to last time
// since `-newSessionEncodedAuthsWithSponsorID:` was called.
//
// -Note: Can call `newSessionEncodedAuthsWithSponsorID:` to get the new authorizations.
//
// - Important: Throws an exception if this function is called before a call
// to `-newSessionEncodedAuthsWithSponsorID:` for the first time.
- (AuthorizationUpdateResult)updateStoredAuthorizations;

// Explicitly indicates that a new tunnel session is about to be started.
- (void)explicitlySetNewSession;

// Indicates start of a new tunnel session.
//
// Returns array of authorizations to be passed to tunnel-core, and populates `sponsorID`
// with the appropriate value depending on the authorizations present.
//
// - Important: Throws an exception if this function is called more than once at the start
// of a tunnel session, unless `newSession` is called beforehand or
// call to `updateStoredAuthorizations` returns AuthorizationUpdateResultNewAuthsAvailable.
- (NSArray<NSString *> *)
newSessionEncodedAuthsWithSponsorID:(NSString *_Nonnull *_Nullable)sponsorID;

// Sets which of the authorizations returned from previous call to `-newSessionEncodedAuthsWithSponsorID:`
// are active.
// 
// - Important: Throws an exception if `newSessionEncodedAuthsWithSponsorID:` has not
// already been called.
- (ActiveAuthorizationResult)
setActiveAuthorizationIDs:(NSArray<NSString *> *_Nonnull)authorizationIds;

// Returns TRUE if latest stored auths contain a subscription auth.
- (BOOL)hasSubscriptionAuth;

// Returns TRUE if the latest stored auths contain a speed-boost or subscription auth.
- (BOOL)hasActiveSpeedBoostOrSubscription;

@end

NS_ASSUME_NONNULL_END
