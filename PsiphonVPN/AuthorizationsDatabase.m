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

#import "AuthorizationsDatabase.h"
#import "Logging.h"
#import "Authorization.h"
#import "NSDate+Comparator.h"

// AuthorizationsDatabase dictionary keys
#define kAuthorizationDictionary        @"kAuthorizationDictionary"
#define kSignedAuthorizations           @"kSignedAuthorizations"


@implementation AuthorizationsDatabase {
    NSMutableDictionary *dictionaryRepresentation;
}

+ (AuthorizationsDatabase *_Nonnull)fromPersistedDefaults {
    AuthorizationsDatabase *instance = [[AuthorizationsDatabase alloc] init];
    instance->dictionaryRepresentation = [[NSMutableDictionary alloc]
      initWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kAuthorizationDictionary]];
    return instance;
}

- (BOOL)isEmpty {
    return (self->dictionaryRepresentation == nil) || ([self->dictionaryRepresentation count] == 0);
}

- (void)removeAuthorizationsNotIn:(NSArray<NSString *> *_Nullable)authorizationIds {
    NSMutableArray<NSString *> *encodedAuthorizationsToPersist = [NSMutableArray arrayWithCapacity:[authorizationIds count]];

    for (NSString *id in authorizationIds) {
        for (Authorization *auth in self.authorizations) {
            if ([auth.ID isEqualToString:id]) {
                [encodedAuthorizationsToPersist addObject:auth.base64Representation];
            }
        }
    }

    // Update underlying dictionary.
    self->dictionaryRepresentation[kSignedAuthorizations] = encodedAuthorizationsToPersist;
}

- (BOOL)hasAuthorizationWithAccessType:(NSString *_Nonnull)accessType {
    for (Authorization *authorization in self.authorizations) {
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

- (NSArray<Authorization *> *_Nullable)authorizations {
    NSArray<NSString *> *encodedAuthorzations = self->dictionaryRepresentation[kSignedAuthorizations];

    if (!encodedAuthorzations || [encodedAuthorzations count] == 0) {
        return nil;
    }

    // Loops through the authorization authorizations in the persisted dictionary, and wraps them in an Authorization class.
    NSArray<Authorization *> *authorizations = [Authorization createFromEncodedAuthorizations:encodedAuthorzations];
    if ([authorizations count] == 0) {
        return nil;
    }
    return authorizations;
}

- (void)addAuthorizations:(NSArray<NSString *> *_Nullable)encodedAuthorizations {
    // Create Authorization objects to validate the authorizations.
    NSArray<Authorization *> *authorizations = [Authorization createFromEncodedAuthorizations:encodedAuthorizations];

    // Initialize authorizationsToPersist with the list of already persisted authorizations.
    NSMutableArray *authorizationsToPersist = [NSMutableArray arrayWithArray:self->dictionaryRepresentation[kSignedAuthorizations]];

    for (Authorization *auth in authorizations) {
        if (auth) {
            [authorizationsToPersist addObject:auth.base64Representation];
        }
    }

    self->dictionaryRepresentation[kSignedAuthorizations] = authorizationsToPersist;
}

- (BOOL)hasActiveAuthorizationForDate:(NSDate *_Nonnull)date {
    if ([self isEmpty]) {
        return FALSE;
    }

    for (Authorization *authorization in self.authorizations) {
        if ([date beforeOrEqualTo:[authorization expires]]) {
            return TRUE;
        }
    }

    return FALSE;
}

@end
