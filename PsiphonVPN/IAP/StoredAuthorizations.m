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

#import "StoredAuthorizations.h"
#import "PsiFeedbackLogger.h"
#import "SubscriptionAuthCheck.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"

@interface StoredAuthorizations ()

@property (nonatomic, nullable, readwrite) Authorization *subscriptionAuth;

@property (nonatomic, nonnull, readwrite) NSSet<Authorization *> *nonSubscriptionAuths;

@property (nonatomic, readwrite) BOOL speedBoostedOrActiveSubscription;

@end

@implementation StoredAuthorizations

- (instancetype)initWithPersistedValues {
    self = [super init];
    if (self) {
        PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc]
                                         initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        
        self.subscriptionAuth = [SubscriptionAuthCheck getLatestAuthorizationNotRejected];
        
        self.nonSubscriptionAuths = [Authorization createFromEncodedAuthorizations:
                                     [sharedDB getNonSubscriptionEncodedAuthorizations].allObjects];
    }
    return self;
}

- (NSSet<NSString *> *)nonSubscriptionAuthIDs {
    return [Authorization authorizationIDsFrom:self.nonSubscriptionAuths];
}

- (NSArray<NSString *> *)encoded {
    NSMutableArray<NSString *> *auths = [NSMutableArray array];
    
    if (self.subscriptionAuth != nil) {
        [auths addObject:self.subscriptionAuth.base64Representation];
    }
    
    [auths addObjectsFromArray:[Authorization encodeAuthorizations:self.nonSubscriptionAuths]];
    
    return auths;
}

- (BOOL)containsAllAuthsFrom:(StoredAuthorizations *_Nonnull)other {
    
    // Checks if `other` has subscription auth not contained in self.
    if (other.subscriptionAuth != nil) {
        if (self.subscriptionAuth.ID != other.subscriptionAuth.ID) {
            // `other` contains subscription auth not contained in self.
            return FALSE;
        }
    }
    
    // Checks if `other` has non-subscription auths not contained in self.
    
    NSSet<NSString *> *selfNonSubAuthIDs = [self nonSubscriptionAuthIDs];
    
    for (NSString *_Nonnull otherAuthID in other.nonSubscriptionAuthIDs) {
        if (![selfNonSubAuthIDs containsObject:otherAuthID]) {
            // `other` contains a non-subscription auth not contained in self.
            return FALSE;
        }
    }
    
    // All auths contained in `other` are also contained in `self`.
    return TRUE;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return TRUE;
    }
    
    if (![object isKindOfClass:[StoredAuthorizations class]]) {
        return FALSE;
    }
    
    return [self isEqualToStoredAuthorizations:(StoredAuthorizations *)object];
}

- (BOOL)isEqualToStoredAuthorizations:(StoredAuthorizations *_Nonnull)other {
    if (self.subscriptionAuth != other.subscriptionAuth &&
        ![self.subscriptionAuth isEqual:other.subscriptionAuth]) {
        return FALSE;
    }
    
    if (![self.nonSubscriptionAuths isEqualToSet:other.nonSubscriptionAuths]) {
        return FALSE;
    }
    
    return TRUE;
}

@end
