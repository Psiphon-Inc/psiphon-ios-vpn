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

#import <Foundation/Foundation.h>

// Authorization AccessTypes

#if DEBUG
#define kAuthorizationAccessTypeApple     @"apple-subscription-test"
#else
#define kAuthorizationAccessTypeApple     @"apple-subscription"
#endif

@interface Authorization : NSObject

@property (nonatomic, readonly, nonnull) NSString *base64Representation;
@property (nonatomic, readonly, nonnull) NSString *ID;
@property (nonatomic, readonly, nonnull) NSString *accessType;
@property (nonatomic, readonly, nonnull) NSDate *expires;

- (instancetype _Nullable)initWithEncodedToken:(NSString *)encodedToken;

@end


@interface Authorizations : NSObject

/** Array of authorization tokens. */
@property (nonatomic, nullable, readonly) NSArray<Authorization *> *tokens;

/**
 * Reads NSUserDefaults and wraps the result in an Authorizations instance.
 * The underlying dictionary can only be manipulated by the provided instance methods.
 * @attention -persistChanges should be called to persist any changes made to the returned
 *            instance to disk.
 * @return An instance of Authorizations class.
 */
+ (Authorizations *_Nonnull)createFromPersistedAuthorizations;

- (BOOL)isEmpty;

/**
 * Given list of authorization IDs, this method removes any persisted authorization token
 * whose ID is not in the provided list.
 * If the provided list is nil or empty, all persisted authorization tokens will be removed.
 * @attention To persist changes made by this function, you should call -persistChanges method.
 * @param authorizationIds NSArray of authorization IDs to keep.
 */
- (void)removeTokensNotIn:(NSArray<NSString *> *_Nullable)authorizationIds;

/**
 * Adds Base64 authorization tokens to the list of authorization tokens.
 * @attention To persist changes made by this function, you should call -persistChanges method.
 * @param encodedTokens Base64 encoded authorization token.
 */
- (void)addTokens:(NSArray<NSString *> *_Nullable)encodedTokens;

/**
 * Returns TRUE if this instance contains an authorization token with the given access type.
 * @param accessType Psiphon authorization access type
 * @return TRUE if contains given access type, FALSE otherwise.
 */
- (BOOL)hasTokenWithAccessType:(NSString *_Nonnull)accessType;

/**
 * Persists changes made to this instance to NSUserDefaults.
 * This is a blocking function.
 * @return TRUE if data was saved to disk successfully, FALSE otherwise.
 */
- (BOOL)persistChanges;

- (BOOL)hasActiveAuthorizationTokenForDate:(NSDate *)date;

@end

#pragma mark - Subscriptions

#define RemoteSubscriptionVerifierSignedAuthorization                @"signed_authorization"
#define RemoteSubscriptionVerifierRequestDate                        @"request_date"
#define RemoteSubscriptionVerifierPendingRenewalInfo                 @"pending_renewal_info"
#define RemoteSubscriptionVerifierPendingRenewalInfoAutoRenewStatus  @"auto_renew_status"

@interface Subscription : NSObject

/** App Store subscription receipt file size. */
@property (nonatomic, nullable, readwrite) NSNumber *appReceiptFileSize;

/**
 * App Store subscription pending renewal info details.
 * @ https://developer.apple.com/library/content/releasenotes/General/ValidateAppStoreReceipt/Chapters/ValidateRemotely.html#//apple_ref/doc/uid/TP40010573-CH104-SW2
 */
@property (nonatomic, nullable, readwrite) NSArray *pendingRenewalInfo;

@property (nonatomic, nullable, readwrite) Authorization *authorizationToken;

/**
 * Reads NSUserDefaults and wraps the result in an Authorizations instance.
 * The underlying dictionary can only be manipulated by changing the properties of this instance.
 * @attention -persistChanges should be called to persist any changes made to the returned instance to disk.
 * @return An instance of Authorizations class.
 */
+ (Subscription *_Nonnull)createFromPersistedSubscription;

/**
 * @return TRUE if underlying dictionary is empty.
 */
- (BOOL)isEmpty;

/**
 * Persists changes made to this instance to NSUserDefaults.
 * This is a blocking function.
 * @return TRUE if data was saved to disk successfully, FALSE otherwise.
 */
- (BOOL)persistChanges;

// TODO: write documentation
- (BOOL)hasActiveSubscriptionTokenForDate:(NSDate *)date;

// TODO: write documentation
- (BOOL)shouldUpdateSubscriptionToken;

@end
