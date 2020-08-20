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

#import "SessionConfigValues.h"
#import "StoredAuthorizations.h"
#import "SubscriptionAuthCheck.h"
#import "PsiphonConfigReader.h"
#import "PsiFeedbackLogger.h"

PsiFeedbackLogType const SessionConfigValuesLogType = @"SessionConfigValues";

@implementation SessionConfigValues {
    PsiphonDataSharedDB *_Nonnull sharedDB;
    
    // latestAuths contains latest stored authorization,
    // following any event that changes authorizations.
    // These events include auth change notifications from the container,
    // or after the processing of `-onActiveAuthorizationIDs:` callback from tunnel-core.
    StoredAuthorizations *_Nonnull latestAuths;
    
    StoredAuthorizations *_Nullable lastSessionAuths;
    
    // hasRetrievedLatestEncodedAuths flag keeps track of whether
    // latest auths have been retrieved (by calling `newSessionEncodedAuthsWithSponsorID:`) or not.
    // This is important for guaranteeing that tunnel-core is using the same authorizations
    // that are present in `storedAuths`.
    BOOL hasRetrievedLatestEncodedAuths;
}

- (instancetype)initWithSharedDB:(PsiphonDataSharedDB *)sharedDB {
    self = [super init];
    if (self) {
        self->sharedDB = sharedDB;
        self->latestAuths = [[StoredAuthorizations alloc] initWithPersistedValues];
        self->hasRetrievedLatestEncodedAuths = FALSE;
        self->lastSessionAuths = nil;
        
        self->_cachedSponsorIDs = [PsiphonConfigReader fromConfigFile].sponsorIds;
        self->_showExpiredSubscriptionAlert = TRUE;
    }
    return self;
}

- (AuthorizationUpdateResult)updateStoredAuthorizations {
    
    if (lastSessionAuths == nil) {
        @throw [NSException exceptionWithName:@"StateInconsistency"
                                       reason:@"undefined state"
                                     userInfo:nil];
    }
    
    latestAuths = [[StoredAuthorizations alloc] initWithPersistedValues];
    
    if ([lastSessionAuths isEqualToStoredAuthorizations:latestAuths]) {
        // Authorizations have not changed since "last session".
        return AuthorizationUpdateResultNoChange;
        
    } else if ([lastSessionAuths containsAllAuthsFrom:latestAuths]) {
        // lastSessionAuths is not equal to latestAuths,
        // but contains all authorization that are in latestAuths.
        // This implies at least one authorization has been marked
        // as invalid since "last session".
        return AuthorizationUpdateResultNoNewAuths;
        
    } else {
        // At this point, latestAuths contains authorizations not contained
        // in lastSessionsAuths.
        
        [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                message:@"Updated stored authorizations"];
        
        hasRetrievedLatestEncodedAuths = FALSE;
        
        return AuthorizationUpdateResultNewAuthsAvailable;
    }
    
}

- (NSArray<NSString *> *)newSessionEncodedAuthsWithSponsorID:(NSString *_Nonnull *_Nullable)sponsorID {
    
    if (hasRetrievedLatestEncodedAuths == TRUE) {
        @throw [NSException exceptionWithName:@"StateInconsistency"
                                       reason:@"undefined state"
                                     userInfo:nil];
    }
    
    // Updates state for a new session
    self->_showExpiredSubscriptionAlert = TRUE;
    lastSessionAuths = latestAuths;
    hasRetrievedLatestEncodedAuths = TRUE;
    
    if (latestAuths.subscriptionAuth == nil) {
        (*sponsorID) = self.cachedSponsorIDs.defaultSponsorId;
    } else {
        (*sponsorID) = self.cachedSponsorIDs.subscriptionSponsorId;
    }
    
    if (latestAuths.subscriptionAuth != nil) {
        [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                 format:@"provided subscription authorization ID:%@",
         latestAuths.subscriptionAuth.ID];
    }
    
    NSSet<NSString *> *_Nonnull nonSubscriptionAuthIDs = latestAuths.nonSubscriptionAuthIDs;
    if ([nonSubscriptionAuthIDs count] > 0) {
        [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                 format:@"provided non-subscription authorization IDs:%@",
         nonSubscriptionAuthIDs];
    }
    
    return [latestAuths encoded];
}

- (ActiveAuthorizationResult)
setActiveAuthorizationIDs:(NSArray<NSString *> *_Nonnull)authorizationIds {
    
    BOOL anyAuthRejected = FALSE;
    ActiveAuthorizationResult result = ActiveAuthorizationResultNone;
    
    // If `hasRetrievedEncodedAuths` is FALSE, then there is no guarantee that the authorizations
    // passed to tunnel-core are the same as the authorizations in `storedAuths`.
    if (hasRetrievedLatestEncodedAuths == FALSE) {
        @throw [NSException exceptionWithName:@"StateInconsistency"
                                       reason:@"undefined state"
                                     userInfo:nil];
    }
    
    // First, identifies if subscription authorization has been marked as invalid
    
    if (lastSessionAuths.subscriptionAuth != nil) {
        if (![authorizationIds containsObject:lastSessionAuths.subscriptionAuth.ID]) {
            
            [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                     format:@"Rejected subscription auth ID '%@'",
             lastSessionAuths.subscriptionAuth.ID];
            
            // Marks the subscription auth ID as rejected.
            [SubscriptionAuthCheck
             addRejectedSubscriptionAuthID:lastSessionAuths.subscriptionAuth.ID];
            
            result = ActiveAuthorizationResultInactiveSubscription;
            
            anyAuthRejected = TRUE;
        }
    }
    
    NSSet<NSString *> *_Nonnull nonSubAuthIDs = lastSessionAuths.nonSubscriptionAuthIDs;
    if ([nonSubAuthIDs count] > 0) {
        
        // Subtracts provided active authorizations `authorizationIds`
        // from the the set of authorizations supplied to tunnel-core.
        // The result is the set of rejected non-subscription authorizations.
        NSMutableSet<NSString *> *rejectedNonSubAuthIDs = [NSMutableSet setWithSet:nonSubAuthIDs];
        [rejectedNonSubAuthIDs minusSet:[NSSet setWithArray:authorizationIds]];
        
        if ([rejectedNonSubAuthIDs count] > 0) {
            
            [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                     format:@"Rejected non-subscription auth IDs: %@",
             rejectedNonSubAuthIDs];
            
            // Immediately removes authorization ids that are not accepted.
            [sharedDB removeNonSubscriptionAuthorizationsNotAccepted:rejectedNonSubAuthIDs];
            
            anyAuthRejected = TRUE;
        }
    }
    
    if (anyAuthRejected) {
        latestAuths = [[StoredAuthorizations alloc] initWithPersistedValues];
    }
    
    return result;
}

- (BOOL)hasSubscriptionAuth {
    return (latestAuths.subscriptionAuth != nil);
}

- (BOOL)hasActiveSpeedBoostOrSubscription {
    
    if (latestAuths.subscriptionAuth != nil) {
        return TRUE;
    }
    
    for (Authorization *nonSubAuth in latestAuths.nonSubscriptionAuths) {
        if (nonSubAuth.accessTypeValue == AuthorizationAccessTypeSpeedBoost ||
            nonSubAuth.accessTypeValue == AuthorizationAccessTypeSpeedBoostTest) {
            return TRUE;
        }
    }
    
    return FALSE;
}

- (void)setShowedExpiredSubscriptionAlertForSession {
    self->_showExpiredSubscriptionAlert = FALSE;
}

@end
