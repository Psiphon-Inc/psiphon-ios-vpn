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

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AuthorizationAccessType) {
    AuthorizationAccessTypeUnknown = 0,
    AuthorizationAccessTypeAppleSubscription = 1,
    AuthorizationAccessTypeAppleSubscriptionTest = 2,
    AuthorizationAccessTypeSpeedBoost = 3,
    AuthorizationAccessTypeSpeedBoostTest = 4
};

@interface Authorization : NSObject

@property (nonatomic, readonly, nonnull) NSString *base64Representation;
@property (nonatomic, readonly, nonnull) NSString *ID;
@property (nonatomic, readonly, nonnull) NSString *accessType;
@property (nonatomic, readonly, nonnull) NSDate *expires;

+ (NSSet<Authorization *> *_Nonnull)createFromEncodedAuthorizations:(NSArray<NSString *> *_Nullable)encodedAuthorizations;

+ (NSArray<NSString *> *_Nonnull)encodeAuthorizations:(NSSet<Authorization *> *_Nullable)auths;

+ (NSSet<NSString *> *_Nonnull)authorizationIDsFrom:(NSSet<Authorization *> *_Nullable)authorizations;

- (instancetype _Nullable)initWithEncodedAuthorization:(NSString *_Nullable)encodedAuthorization;

- (AuthorizationAccessType)accessTypeValue;

@end

NS_ASSUME_NONNULL_END
