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

#import "AuthorizationToken.h"
#import "PsiFeedbackLogger.h"
#import "NSDateFormatter+RFC3339.h"

@interface AuthorizationToken ()

@property (nonatomic, readwrite) NSString *base64Representation;
@property (nonatomic, readwrite) NSString *ID;
@property (nonatomic, readwrite) NSString *accessType;
@property (nonatomic, readwrite) NSDate *expires;

@end

@implementation AuthorizationToken

+ (NSArray<AuthorizationToken *> *_Nonnull)createFromEncodedTokens:(NSArray<NSString *> *)encodedAuthorizations {
    NSMutableArray<AuthorizationToken *> *authorizations = [NSMutableArray array];
    for (NSString *encodedToken in encodedAuthorizations) {
        AuthorizationToken *authorization = [[AuthorizationToken alloc] initWithEncodedToken:encodedToken];
        if (authorization) {
            [authorizations addObject:authorization];
        }
    }
    return authorizations;
}

- (instancetype _Nullable)initWithEncodedToken:(NSString *)encodedToken {
    self = [super init];
    if (self) {
        if (!encodedToken || [encodedToken length] == 0) {
            return nil;
        }

        // Decode Bae64 Authorization.
        NSError *error;
        NSData *data = [[NSData alloc] initWithBase64EncodedString:encodedToken options:0];
        NSDictionary *authorizationObjectDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error) {
            [PsiFeedbackLogger error:@"failed to parse authorization token:%@", error];
            return nil;
        }

        NSDictionary *authDict = authorizationObjectDict[@"Authorization"];

        // Store base64 representation
        self.base64Representation = encodedToken;

        // Get ID
        self.ID = authDict[@"ID"];
        if ([self.ID length] == 0) {
            [PsiFeedbackLogger error:@"authorization token 'ID' is empty"];
            return nil;
        }

        // Get AccessType
        self.accessType = authDict[@"AccessType"];
        if ([self.accessType length] == 0) {
            [PsiFeedbackLogger error:@"authorization token 'AccessType' is empty"];
            return nil;
        }

        // Get Expires date
        NSString *authExpiresDateString = (NSString *) authDict[@"Expires"];
        if ([authExpiresDateString length] == 0) {
            [PsiFeedbackLogger error:@"authorization token 'Expires' is empty"];
            return nil;
        }
        self.expires = [[NSDateFormatter sharedRFC3339DateFormatter] dateFromString:authExpiresDateString];
        if (!self.expires) {
            [PsiFeedbackLogger error:@"authorization token failed to parse RFC3339 date string (%@)", authExpiresDateString];
            return nil;
        }
    }
    return self;
}

@end

