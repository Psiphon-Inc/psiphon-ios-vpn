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
#import "UserDefaultsModelProtocol.h"
#import "AuthorizationToken.h"


@interface Authorizations : NSObject <UserDefaultsModelProtocol>

/** Array of authorization tokens. */
@property (nonatomic, nullable, readonly) NSArray<AuthorizationToken *> *tokens;

/**
 * Reads NSUserDefaults and wraps the result in an Authorizations instance.
 * The underlying dictionary can only be manipulated by the provided instance methods.
 * @attention -persistChanges should be called to persist any changes made to the returned
 *            instance to disk.
 * @return An instance of Authorizations class.
 */
+ (Authorizations *_Nonnull)fromPersistedDefaults;

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

- (BOOL)hasActiveAuthorizationTokenForDate:(NSDate *_Nonnull)date;

@end

#pragma mark - Subscriptions

