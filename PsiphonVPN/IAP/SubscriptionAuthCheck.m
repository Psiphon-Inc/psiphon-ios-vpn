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

#import "SubscriptionAuthCheck.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "PsiFeedbackLogger.h"
#import "Logging.h"

PsiFeedbackLogType const SubscriptionAuthCheckLogType = @"SubscriptionAuthCheck";


@implementation SubscriptionAuthCheck

+ (Authorization *_Nullable)getLatestAuthorizationNotRejected {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc]
                                     initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    
    NSData *_Nullable storedData = [sharedDB getSubscriptionAuths];
    if (storedData == nil) {
        return nil;
    }

    // Dictionary has the Swift type: `[OriginalTransactionID: SubscriptionPurchaseAuthState]`.
    // Data is encoded as an array [OriginalTransactionID, SubscriptionPurchaseAuthState, ...].
    NSError *_Nullable err;
    NSArray *subsAuthDict = (NSArray *)[NSJSONSerialization JSONObjectWithData:storedData
                                                                       options:kNilOptions
                                                                         error:&err];
    if (err != nil) {
        [PsiFeedbackLogger errorWithType:SubscriptionAuthCheckLogType
                                 message:@"Failed to decode stored data"
                                  object:err];
        return nil;
    }
    
    if ([subsAuthDict count] < 2) {
        return nil;
    }
    
    NSMutableArray<Authorization *> *authorizations = [NSMutableArray array];
    
    for (int i = 1; i < [subsAuthDict count]; i += 2) {
        
        NSDictionary *purchaseAuthState = (NSDictionary *)subsAuthDict[i];
        
        NSDictionary *_Nullable signedAuthorizationEnum = purchaseAuthState[@"signedAuthorization"];
        
        if (signedAuthorizationEnum == nil) {
            continue;
        }
        
        NSString *_Nullable state = signedAuthorizationEnum[@"state"];
        if (state == nil) {
            [PsiFeedbackLogger errorWithType:SubscriptionAuthCheckLogType
                                     message:@"'state' missing"];
            continue;
        }
        
        if (![@"authorization" isEqualToString:state]) {
            continue;
        }
        
        NSString *_Nullable base64Auth = signedAuthorizationEnum[@"authorization"];
        if (base64Auth == nil) {
            [PsiFeedbackLogger errorWithType:SubscriptionAuthCheckLogType
                                     message:@"'authorization' missing"];
            continue;
        }
        
        Authorization *_Nullable decodedAuth = [[Authorization alloc]
                                                initWithEncodedAuthorization:base64Auth];
        if (decodedAuth == nil) {
            [PsiFeedbackLogger errorWithType:SubscriptionAuthCheckLogType
                                     format:@"failed to decode '%@'", base64Auth];
            continue;
        }
        
        [authorizations addObject:decodedAuth];
    }
    
    Authorization *_Nullable authWithLatestExpiry = nil;
    for (Authorization *auth in authorizations) {
        if (authWithLatestExpiry == nil) {
            authWithLatestExpiry = auth;
            continue;
        }
        
        if ([authWithLatestExpiry.expires compare:auth.expires] == NSOrderedAscending) {
            authWithLatestExpiry = auth;
        }
    }
    
    if (authWithLatestExpiry == nil) {
        LOG_DEBUG(@"authWithLatestExpiry is 'nil`");
        return nil;
    }
    
    NSArray<NSString *> *_Nonnull rejectedAuthIDs = [sharedDB
                                                      getRejectedSubscriptionAuthorizationIDs];
    
    // Checks if authorization is already rejected.
    for (NSString *rejectedAuthID in rejectedAuthIDs) {
        if ([authWithLatestExpiry.ID isEqualToString: rejectedAuthID]) {
            
            [PsiFeedbackLogger
             infoWithType:SubscriptionAuthCheckLogType
             format:@"Subscription auth with ID '%@' matched rejected auth ID '%@'",
             authWithLatestExpiry.ID, rejectedAuthID];
            
            return nil;
        }
    }
    
    return authWithLatestExpiry;
}

+ (void)addRejectedSubscriptionAuthID:(NSString *)authorizationID {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc]
                                     initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    
    [sharedDB insertRejectedSubscriptionAuthorizationID: authorizationID];
}

@end
