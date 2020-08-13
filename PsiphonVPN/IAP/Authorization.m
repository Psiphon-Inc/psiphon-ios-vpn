/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "Authorization.h"
#import "PsiFeedbackLogger.h"
#import "NSDate+PSIDateExtension.h"

@interface Authorization ()

@property (nonatomic, readwrite) NSString *base64Representation;
@property (nonatomic, readwrite) NSString *ID;
@property (nonatomic, readwrite) NSString *accessType;
@property (nonatomic, readwrite) NSDate *expires;

@end

@implementation Authorization

+ (NSSet<Authorization *> *_Nonnull)createFromEncodedAuthorizations:(NSArray<NSString *> *_Nullable)encodedAuthorizations {
    NSMutableSet<Authorization *> *authsSet = [NSMutableSet set];

    [encodedAuthorizations enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop) {
        Authorization *_Nullable auth = [[Authorization alloc] initWithEncodedAuthorization:obj];
        if (auth) {
            [authsSet addObject:auth];
        }
    }];

    return authsSet;
}

+ (NSArray<NSString *> *_Nonnull)encodeAuthorizations:(NSSet<Authorization *> *_Nullable)auths {
    NSMutableArray<NSString *> *encodedAuths = [NSMutableArray array];
    [auths enumerateObjectsUsingBlock:^(Authorization *obj, BOOL *stop) {
        [encodedAuths addObject:obj.base64Representation];
    }];
    return encodedAuths;
}

+ (NSSet<NSString *> *_Nonnull)authorizationIDsFrom:(NSSet<Authorization *> *_Nullable)authorizations {
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    [authorizations enumerateObjectsUsingBlock:^(Authorization *obj, BOOL *stop) {
        [ids addObject:obj.ID];
    }];
    return ids;
}

- (instancetype _Nullable)initWithEncodedAuthorization:(NSString *)encodedAuthorization {
    self = [super init];
    if (self) {
        if (!encodedAuthorization || [encodedAuthorization length] == 0) {
            return nil;
        }

        // Decode Bae64 Authorization.
        NSError *error;
        NSData *data = [[NSData alloc] initWithBase64EncodedString:encodedAuthorization options:0];
        NSDictionary *authorizationObjectDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error) {
            [PsiFeedbackLogger error:@"failed to parse authorization:%@", error];
            return nil;
        }

        NSDictionary *authDict = authorizationObjectDict[@"Authorization"];

        // Store base64 representation
        self.base64Representation = encodedAuthorization;

        // Get ID
        self.ID = authDict[@"ID"];
        if ([self.ID length] == 0) {
            [PsiFeedbackLogger error:@"authorization 'ID' is empty"];
            return nil;
        }

        // Get AccessType
        self.accessType = authDict[@"AccessType"];
        if ([self.accessType length] == 0) {
            [PsiFeedbackLogger error:@"authorization 'AccessType' is empty"];
            return nil;
        }
        
        

        // Get Expires date
        NSString *authExpiresDateString = (NSString *) authDict[@"Expires"];
        if ([authExpiresDateString length] == 0) {
            [PsiFeedbackLogger error:@"authorization 'Expires' is empty"];
            return nil;
        }

        self.expires = [NSDate fromRFC3339String:authExpiresDateString];
        if (!self.expires) {
            [PsiFeedbackLogger error:@"authorization failed to parse RFC3339 date string (%@)", authExpiresDateString];
            return nil;
        }
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    // Checks for trivial equality.
    if (self == object) {
        return TRUE;
    }

    // Ignores objects that are not of type Authorization.
    if (![(NSObject *)object isKindOfClass:[Authorization class]]) {
        return FALSE;
    }

    // Authorization IDs are guaranteed to be unique.
    return [self.ID isEqualToString:((Authorization *)object).ID];
}

- (NSUInteger)hash {
    // Authorization ID is itself unique.
    return [self.ID hash];
}

- (AuthorizationAccessType)accessTypeValue {
    if ([self.accessType isEqualToString:@"apple-subscription"]) {
        return AuthorizationAccessTypeAppleSubscription;
        
    } else if ([self.accessType isEqualToString:@"apple-subscription-test"]) {
        return AuthorizationAccessTypeAppleSubscriptionTest;
        
    } else if ([self.accessType isEqualToString:@"speed-boost"]) {
        return AuthorizationAccessTypeSpeedBoost;
        
    } else if ([self.accessType isEqualToString:@"speed-boost-test"]) {
        return AuthorizationAccessTypeSpeedBoostTest;
        
    } else {
        return AuthorizationAccessTypeUnknown;
    }
}

@end
