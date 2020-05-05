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

@implementation StoredAuthorizations

- (instancetype)initWithPersistedValues {
    self = [super init];
    if (self) {
        PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc]
                                         initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        
        self.subscriptionAuth = [SubscriptionAuthCheck getLatestAuthrizationNotRejected];
        
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

@end
