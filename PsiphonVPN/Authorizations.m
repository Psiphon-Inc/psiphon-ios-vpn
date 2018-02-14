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

// Subscription dictionary keys
#define kSubscriptionDictionary         @"kSubscriptionDictionary"
#define kAppReceiptFileSize             @"kAppReceiptFileSize"
#define kPendingRenewalInfo             @"kPendingRenewalInfo"
#define kSubscriptionAuthorizationToken @"kSubscriptionAuthorizationToken"

// Authorizations dictionary keys
#define kAuthorizationDictionary        @"kAuthorizationDictionary"
#define kSignedAuthorizations           @"kSignedAuthorizations"


#pragma mark - Authorization Token

@interface Authorization ()

@property (nonatomic, readwrite) NSString *base64Representation;
@property (nonatomic, readwrite) NSString *ID;
@property (nonatomic, readwrite) NSString *accessType;
@property (nonatomic, readwrite) NSDate *expires;

@end

@implementation Authorization

+ (NSArray<Authorization *> *_Nonnull)createFromEncodedTokens:(NSArray<NSString *> *)encodedAuthorizations {
    NSMutableArray<Authorization *> *authorizations = [NSMutableArray array];
    for (NSString *encodedToken in encodedAuthorizations) {
        Authorization *authorization = [[Authorization alloc] initWithEncodedToken:encodedToken];
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
            LOG_ERROR(@"failed to parse authorization token:%@", error);
            return nil;
        }

        NSDictionary *authDict = authorizationObjectDict[@"Authorization"];

        // Store base64 representation
        self.base64Representation = encodedToken;

        // Get ID
        self.ID = authDict[@"ID"];
        if ([self.ID length] == 0) {
            LOG_ERROR(@"authorization token 'ID' is empty");
            return nil;
        }

        // Get AccessType
        self.accessType = authDict[@"AccessType"];
        if ([self.accessType length] == 0) {
            LOG_ERROR(@"authorization token 'AccessType' is empty");
            return nil;
        }

        // Get Expires date
        NSString *authExpiresDateString = (NSString *) authDict[@"Expires"];
        if ([authExpiresDateString length] == 0) {
            LOG_ERROR(@"authorization token 'Expires' is empty");
            return nil;
        }
        self.expires = [[NSDateFormatter sharedRFC3339DateFormatter] dateFromString:authExpiresDateString];
        if (!self.expires) {
            LOG_ERROR(@"authorization token failed to parse RFC3339 date string (%@)", authExpiresDateString);
            return nil;
        }
    }
    return self;
}

@end

#pragma mark - Authorizations

@implementation Authorizations {
    NSMutableDictionary *dictionaryRepresentation;
}

+ (Authorizations *_Nonnull)createFromPersistedAuthorizations {
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
        for (Authorization *token in self.tokens) {
            if ([token.ID isEqualToString:id]) {
                [encodedTokensToPersist addObject:token.base64Representation];
            }
        }
    }

    // Update underlying dictionary.
    self->dictionaryRepresentation[kSignedAuthorizations] = encodedTokensToPersist;
}

- (BOOL)hasTokenWithAccessType:(NSString *_Nonnull)accessType {
    for (Authorization *authorization in self.tokens) {
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

- (NSArray<Authorization *> *_Nullable)tokens {
    NSArray<NSString *> *encodedTokens = self->dictionaryRepresentation[kSignedAuthorizations];

    if (!encodedTokens || [encodedTokens count] == 0) {
        return nil;
    }

    // Loops through the authorization tokens in the persisted dictionary, and wraps them in an Authorization class.
    NSArray<Authorization *> *authorizations = [Authorization createFromEncodedTokens:encodedTokens];
    if ([authorizations count] == 0) {
        return nil;
    }
    return authorizations;
}

- (void)addTokens:(NSArray<NSString *> *_Nullable)encodedTokens {
    // Create Authorization objects to validate the tokens.
    NSArray<Authorization *> *tokens = [Authorization createFromEncodedTokens:encodedTokens];

    // Initialize tokensToPersist with the list of already persisted tokens.
    NSMutableArray *tokensToPersist = [NSMutableArray arrayWithArray:self->dictionaryRepresentation[kSignedAuthorizations]];

    for (Authorization *token in tokens) {
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

    for (Authorization *authorization in self.tokens) {
        if ([date compare:[authorization expires]] != NSOrderedDescending) {
            return TRUE;
        }
    }

    return FALSE;
}

@end

#pragma mark - Subscription

@implementation Subscription {
    NSMutableDictionary *dictionaryRepresentation;
}

+ (Subscription *_Nonnull)createFromPersistedSubscription {
    Subscription *instance = [[Subscription alloc] init];
    NSDictionary *persistedDic = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSubscriptionDictionary];
    instance->dictionaryRepresentation = [[NSMutableDictionary alloc] initWithDictionary:persistedDic];
    return instance;
}

- (BOOL)isEmpty {
    return (self->dictionaryRepresentation == nil) || ([self->dictionaryRepresentation count] == 0);
}

- (BOOL)persistChanges {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:self->dictionaryRepresentation forKey:kSubscriptionDictionary];
    return [userDefaults synchronize];
}

- (NSNumber *_Nullable)appReceiptFileSize {
    return self->dictionaryRepresentation[kAppReceiptFileSize];
}

- (void)setAppReceiptFileSize:(NSNumber *_Nullable)fileSize {
    self->dictionaryRepresentation[kAppReceiptFileSize] = fileSize;
}

- (NSArray *_Nullable)pendingRenewalInfo {
    return self->dictionaryRepresentation[kPendingRenewalInfo];
}

- (void)setPendingRenewalInfo:(NSArray *)pendingRenewalInfo {
    self->dictionaryRepresentation[kPendingRenewalInfo] = pendingRenewalInfo;
}

- (Authorization *)authorizationToken {
   return [[Authorization alloc] initWithEncodedToken:self->dictionaryRepresentation[kSubscriptionAuthorizationToken]];
}

- (void)setAuthorizationToken:(Authorization *)authorizationToken {
    self->dictionaryRepresentation[kSubscriptionAuthorizationToken] = authorizationToken.base64Representation;
}

- (BOOL)hasActiveSubscriptionTokenForDate:(NSDate *)date {

    if ([self isEmpty]) {
        return FALSE;
    }

    if ([date compare:[self.authorizationToken expires]] != NSOrderedDescending) {
        return TRUE;
    }
    return FALSE;
}

- (BOOL)shouldUpdateSubscriptionToken {
    // If no receipt - NO
    NSURL *URL = [NSBundle mainBundle].appStoreReceiptURL;
    NSString *path = URL.path;
    const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil];
    if (!exists) {
        LOG_DEBUG_NOTICE(@"receipt does not exist");
        return NO;
    }

    // There's receipt but no subscription persisted - YES
    if([self isEmpty]) {
        LOG_DEBUG_NOTICE(@"receipt exist by no subscription persisted");
        return YES;
    }

    // Receipt file size has changed since last check - YES
    NSNumber *appReceiptFileSize = nil;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:nil];
    if ([appReceiptFileSize unsignedIntValue] != [self.appReceiptFileSize unsignedIntValue]) {
        LOG_DEBUG_NOTICE(@"receipt file size changed (%@) since last check (%@)", appReceiptFileSize, self.appReceiptFileSize);
        return YES;
    }

    // If user has an active authorization for date - NO
    if ([self hasActiveSubscriptionTokenForDate:[NSDate date]]) {
        LOG_DEBUG_NOTICE(@"device has active authorization for date");
        return NO;
    }

    // If expired and pending renewal info is missing - YES
    if(!self.pendingRenewalInfo) {
        LOG_DEBUG_NOTICE(@"pending renewal info is missing");
        return YES;
    }

    // If expired but user's last known intention was to auto-renew - YES
    if([self.pendingRenewalInfo count] == 1
      && [self.pendingRenewalInfo[0] isKindOfClass:[NSDictionary class]]) {

        NSString *autoRenewStatus = [self.pendingRenewalInfo[0] objectForKey:kRemoteSubscriptionVerifierPendingRenewalInfoAutoRenewStatus];
        if (autoRenewStatus && [autoRenewStatus isEqualToString:@"1"]) {
            LOG_DEBUG_NOTICE(@"subscription expired but user's last known intention is to auto-renew");
            return YES;
        }
    }

    LOG_DEBUG_NOTICE(@"authorization token update not needed");
    return NO;
}

- (NSError *)updateSubscriptionWithRemoteAuthDict:(NSDictionary *)remoteAuthDict {

    if (!remoteAuthDict) {
        return nil;
    }
    
    // Gets app subscription receipt file size.
    NSError *err;
    NSNumber *appReceiptFileSize = nil;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:&err];
    if (err) {
        return err;
    }

    // Updates subscription dictionary.
    [self setAppReceiptFileSize:appReceiptFileSize];
    [self setPendingRenewalInfo:remoteAuthDict[kRemoteSubscriptionVerifierPendingRenewalInfo]];
    Authorization *authorizationToken = [[Authorization alloc]
      initWithEncodedToken:remoteAuthDict[kRemoteSubscriptionVerifierSignedAuthorization]];
    [self setAuthorizationToken:authorizationToken];

    return nil;
}


@end
