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

#import "Authorizations.h"
#import "NSDateFormatter+RFC3339.h"
#import "Logging.h"
#import "AuthorizationToken.h"

// Authorizations dictionary keys
#define kAuthorizationDictionary        @"kAuthorizationDictionary"
#define kSignedAuthorizations           @"kSignedAuthorizations"


#pragma mark - Authorizations

@implementation Authorizations {
    NSMutableDictionary *dictionaryRepresentation;
}

+ (Authorizations *_Nonnull)fromPersistedDefaults {
    Authorizations *instance = [[Authorizations alloc] init];
    instance->dictionaryRepresentation = [[NSMutableDictionary alloc]
      initWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kAuthorizationDictionary]];
    return instance;
}

- (BOOL)isEmpty {
    return (self->dictionaryRepresentation == nil) || ([self->dictionaryRepresentation count] == 0);
}

- (void)removeTokensNotIn:(NSArray<NSString *> *_Nullable)authorizationIds {
    NSMutableArray<NSString *> *encodedTokensToPersist = [NSMutableArray arrayWithCapacity:[authorizationIds count]];

    for (NSString *id in authorizationIds) {
        for (AuthorizationToken *token in self.tokens) {
            if ([token.ID isEqualToString:id]) {
                [encodedTokensToPersist addObject:token.base64Representation];
            }
        }
    }

    // Update underlying dictionary.
    self->dictionaryRepresentation[kSignedAuthorizations] = encodedTokensToPersist;
}

- (BOOL)hasTokenWithAccessType:(NSString *_Nonnull)accessType {
    for (AuthorizationToken *authorization in self.tokens) {
        if ([authorization.accessType isEqualToString:accessType]) {
            return TRUE;
        }
    }
    return FALSE;
}

- (BOOL)persistChanges {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:self->dictionaryRepresentation forKey:kAuthorizationDictionary];
    return [userDefaults synchronize];
}

#pragma mark - Property Getters and setters

- (NSArray<AuthorizationToken *> *_Nullable)tokens {
    NSArray<NSString *> *encodedTokens = self->dictionaryRepresentation[kSignedAuthorizations];

    if (!encodedTokens || [encodedTokens count] == 0) {
        return nil;
    }

    // Loops through the authorization tokens in the persisted dictionary, and wraps them in an AuthorizationToken class.
    NSArray<AuthorizationToken *> *authorizations = [AuthorizationToken createFromEncodedTokens:encodedTokens];
    if ([authorizations count] == 0) {
        return nil;
    }
    return authorizations;
}

- (void)addTokens:(NSArray<NSString *> *_Nullable)encodedTokens {
    // Create AuthorizationToken objects to validate the tokens.
    NSArray<AuthorizationToken *> *tokens = [AuthorizationToken createFromEncodedTokens:encodedTokens];

    // Initialize tokensToPersist with the list of already persisted tokens.
    NSMutableArray *tokensToPersist = [NSMutableArray arrayWithArray:self->dictionaryRepresentation[kSignedAuthorizations]];

    for (AuthorizationToken *token in tokens) {
        if (token) {
            [tokensToPersist addObject:token.base64Representation];
        }
    }

    self->dictionaryRepresentation[kSignedAuthorizations] = tokensToPersist;
}

- (BOOL)hasActiveAuthorizationTokenForDate:(NSDate *)date {
    if ([self isEmpty]) {
        return FALSE;
    }

    for (AuthorizationToken *authorization in self.tokens) {
        if ([date compare:[authorization expires]] != NSOrderedDescending) {
            return TRUE;
        }
    }

    return FALSE;
}

@end
