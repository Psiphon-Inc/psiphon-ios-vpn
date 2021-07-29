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

#import "SharedAuthorization+CoreDataClass.h"

NSString * const AppleSubscriptionAccessTypeValue = @"apple-subscription";
NSString * const AppleSubscriptionTestAccessTypeValue = @"apple-subscription-test";
NSString * const SpeedBoostAccessTypeValue = @"speed-boost";
NSString * const SpeedBoostTestAccessTypeValue = @"speed-boost-test";

#if DEBUG || DEV_RELEASE
NSString * const SubscriptionAccessType = AppleSubscriptionTestAccessTypeValue;
NSString * const SpeedBoostAccessType = SpeedBoostTestAccessTypeValue;
#else
NSString * const SubscriptionAccessType = AppleSubscriptionAccessType;
NSString * const SpeedBoostAccessType = SpeedBoostAccessType;
#endif

@implementation SharedAuthorization

- (AuthorizationAccessType)accessTypeValue {
    return [SharedAuthorization accessTypeForString:self.accessType];
}

+ (AuthorizationAccessType)accessTypeForString:(NSString *_Nullable)accessType {
    if ([accessType isEqualToString:AppleSubscriptionAccessTypeValue]) {
        return AuthorizationAccessTypeAppleSubscription;
        
    } else if ([accessType isEqualToString:AppleSubscriptionTestAccessTypeValue]) {
        return AuthorizationAccessTypeAppleSubscriptionTest;
        
    } else if ([accessType isEqualToString:SpeedBoostAccessTypeValue]) {
        return AuthorizationAccessTypeSpeedBoost;
        
    } else if ([accessType isEqualToString:SpeedBoostTestAccessTypeValue]) {
        return AuthorizationAccessTypeSpeedBoostTest;
        
    } else {
        return AuthorizationAccessTypeUnknown;
    }
}

@end
