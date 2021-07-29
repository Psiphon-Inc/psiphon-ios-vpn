/*
 * Copyright (c) 2021, Psiphon Inc.
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
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

/*
 Authorization AccessType string values.
 */

FOUNDATION_EXPORT NSString * const AppleSubscriptionAccessTypeValue;
FOUNDATION_EXPORT NSString * const AppleSubscriptionTestAccessTypeValue;
FOUNDATION_EXPORT NSString * const SpeedBoostAccessTypeValue;
FOUNDATION_EXPORT NSString * const SpeedBoostTestAccessTypeValue;

FOUNDATION_EXPORT NSString * const SubscriptionAccessType;
FOUNDATION_EXPORT NSString * const SpeedBoostAccessType;

typedef NS_ENUM(NSInteger, AuthorizationAccessType) {
    AuthorizationAccessTypeUnknown = 0,
    AuthorizationAccessTypeAppleSubscription = 1,
    AuthorizationAccessTypeAppleSubscriptionTest = 2,
    AuthorizationAccessTypeSpeedBoost = 3,
    AuthorizationAccessTypeSpeedBoostTest = 4
};

/// NSManagedObject is not thread-safe.
@interface SharedAuthorization : NSManagedObject

/// AuthorizationAccessType value.
- (AuthorizationAccessType)accessTypeValue;

/// Maps accessType string value into AuthorizationAccessType enum.
+ (AuthorizationAccessType)accessTypeForString:(NSString *_Nullable)accessType;

@end

NS_ASSUME_NONNULL_END

#import "SharedAuthorization+CoreDataProperties.h"
