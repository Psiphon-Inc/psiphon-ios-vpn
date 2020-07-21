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
    StoredAuthorizations *_Nonnull storedAuths;
    
    // hasRetrievedLatestEncodedAuths flag keeps track of whether
    // latest auths have been retrieved (by calling `getEncodedAuthsWithSponsorID:`) or not.
    // This is important for guaranteeing that tunnel-core is using the same authorizations
    // that are present in `storedAuths`.
    BOOL hasRetrievedLatestEncodedAuths;
}

- (instancetype)initWithSharedDB:(PsiphonDataSharedDB *)sharedDB {
    self = [super init];
    if (self) {
        self->sharedDB = sharedDB;
        self->storedAuths = [[StoredAuthorizations alloc] initWithPersistedValues];
        self->hasRetrievedLatestEncodedAuths = FALSE;
        
        self->_cachedSponsorIDs = [PsiphonConfigReader fromConfigFile].sponsorIds;

    }
    return self;
}

- (BOOL)updateStoredAuthorizations {
    
    StoredAuthorizations *_Nonnull updatedStoredAuths = [[StoredAuthorizations alloc]
                                                         initWithPersistedValues];
    
    if ([updatedStoredAuths isEqualToStoredAuthorizations:storedAuths]) {
        return FALSE;
    } else {
        [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                message:@"Updated stored authorizations"];
        
        storedAuths = updatedStoredAuths;
        hasRetrievedLatestEncodedAuths = FALSE;
        return TRUE;
    }
    
}

- (NSArray<NSString *> *)getEncodedAuthsWithSponsorID:(NSString *_Nonnull *_Nullable)sponsorID {
    
    if (hasRetrievedLatestEncodedAuths) {
        @throw [NSException exceptionWithName:@"StateInconsistency"
                                       reason:@"undefined state"
                                     userInfo:nil];
    }
    
    hasRetrievedLatestEncodedAuths = TRUE;
    
    if (storedAuths.subscriptionAuth == nil) {
        (*sponsorID) = self.cachedSponsorIDs.defaultSponsorId;
    } else {
        (*sponsorID) = self.cachedSponsorIDs.subscriptionSponsorId;
    }
    
    if (storedAuths.subscriptionAuth != nil) {
        [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                 format:@"provided subscription authorization ID:%@",
         storedAuths.subscriptionAuth.ID];
    }
    
    NSSet<NSString *> *_Nonnull nonSubscriptionAuthIDs = storedAuths.nonSubscriptionAuthIDs;
    if ([nonSubscriptionAuthIDs count] > 0) {
        [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                 format:@"provided non-subscription authorization IDs:%@",
         nonSubscriptionAuthIDs];
    }
    
    return [storedAuths encoded];
}

- (ActiveAuthorizationResult)
setActiveAuthorizationIDs:(NSArray<NSString *> *_Nonnull)authorizationIds; {
    
    ActiveAuthorizationResult result = ActiveAuthorizationResultNone;
    
    // If `hasRetrievedEncodedAuths` is FALSE, then there is no guarantee that the authorizations
    // passed to tunnel-core are the same as the authorizations in `storedAuths`.
    if (!hasRetrievedLatestEncodedAuths) {
        @throw [NSException exceptionWithName:@"StateInconsistency"
                                       reason:@"undefined state"
                                     userInfo:nil];
    }
    
    // First, identifies if subscription authorization has been marked as invalid
    
    if (storedAuths.subscriptionAuth != nil) {
        if (![authorizationIds containsObject:storedAuths.subscriptionAuth.ID]) {
            
            [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                     format:@"Rejected subscription auth ID '%@'",
             storedAuths.subscriptionAuth.ID];
            
            // Marks the subscription auth ID as rejected.
            [SubscriptionAuthCheck addRejectedSubscriptionAuthID:storedAuths.subscriptionAuth.ID];
            
            result = ActiveAuthorizationResultInactiveSubscription;
        }
    }
    
    NSSet<NSString *> *_Nonnull nonSubAuthIDs = storedAuths.nonSubscriptionAuthIDs;
    if ([nonSubAuthIDs count] > 0) {
        
        // Subtracts provided active authorizations `authorizationIds`
        // from the the set of authorizations supplied to tunnel-core.
        // The result is the set of rejected non-subscription authorizations.
        NSMutableSet<NSString *> *rejectedNonSubAuthIDs = [NSMutableSet setWithSet:nonSubAuthIDs];
        [rejectedNonSubAuthIDs minusSet:[NSSet setWithArray:authorizationIds]];
        
        if ([rejectedNonSubAuthIDs count] > 0) {
            // Immediately removes authorization ids that are not accepted.
            [sharedDB removeNonSubscriptionAuthorizationsNotAccepted:rejectedNonSubAuthIDs];
            
            [PsiFeedbackLogger infoWithType:SessionConfigValuesLogType
                                     format:@"Rejected non-subscription auth IDs: %@",
             rejectedNonSubAuthIDs];
        }
    }
    
    return result;
}

- (BOOL)hasSubscriptionAuth {
    return (storedAuths.subscriptionAuth != nil);
}

@end
