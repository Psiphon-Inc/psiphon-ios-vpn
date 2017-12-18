 /*
 * Copyright (c) 2017, Psiphon Inc.
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

#import "IAPSubscriptionHelper.h"
#import "Logging.h"
#import <StoreKit/StoreKit.h>
#import "PsiphonDataSharedDB.h"
#import "NSDateFormatter+RFC3339.h"
#import "NoticeLogger.h"

@implementation IAPSubscriptionHelper

+ (BOOL)shouldUpdateSubscriptionDictinary:(NSDictionary*)subscriptionDict withPendingRenewalInfoCheck:(BOOL)check {
    // If no receipt - NO
    NSURL *URL = [NSBundle mainBundle].appStoreReceiptURL;
    NSString *path = URL.path;
    const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil];
    if (!exists) {
        return NO;
    }

    // There's receipt but no subscriptionDictionary - YES
    if(!subscriptionDict) {
        return YES;
    }

    // Receipt file size has changed since last check - YES
    NSNumber* appReceiptFileSize = nil;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:nil];
    NSNumber* dictAppReceiptFileSize = [subscriptionDict objectForKey:kAppReceiptFileSize];
    if ([appReceiptFileSize unsignedIntValue] != [dictAppReceiptFileSize unsignedIntValue]) {
        return YES;
    }

    // If user has an active subscription for date - NO
    if ([[self class] hasActiveSubscriptionForDate:[NSDate date] inDict:subscriptionDict]) {
        return NO;
    }

    // else we have an expired subscription
    if(check) {
        NSArray *pending_renewal_info = [subscriptionDict objectForKey:kPendingRenewalInfo];

        // If expired and pending renewal info is missing - we are
        if(!pending_renewal_info) {
            return YES;
        }

        // If expired but user's last known intention was to auto-renew - YES
        if([pending_renewal_info count] == 1 && [pending_renewal_info[0] isKindOfClass:[NSDictionary class]]) {
            NSString *auto_renew_status = [pending_renewal_info[0] objectForKey:kAutoRenewStatus];
            if (auto_renew_status && [auto_renew_status isEqualToString:@"1"]) {
                return YES;
            }
        }
    }

    return NO;
}

+ (NSDictionary*)sharedSubscriptionDictionary {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    return [sharedDB getSubscriptionDictionary];
}

+ (void)storesharedSubscriptionDisctionary:(NSDictionary*)dict {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    [sharedDB updateSubscriptionDictionary:dict];
}


+ (BOOL)hasActiveSubscriptionForDate:(NSDate*)date {
    NSDictionary* dict = [[self class] sharedSubscriptionDictionary];
    return [[self class] hasActiveSubscriptionForDate:date inDict:dict];
}

+ (BOOL) hasActiveSubscriptionForDate:(NSDate*)date inDict:(NSDictionary*)subscriptionDict {

    if(!subscriptionDict) {
        return NO;
    }
    // Allow some tolerance IRL.
#if !DEBUG
    date = [date dateByAdingTimeInterval:-SUBSCRIPTION_CHECK_GRACE_PERIOD_INTERVAL];
#endif

    NSDate *latestExpirationDate = [subscriptionDict objectForKey:kLatestExpirationDate];

    if(latestExpirationDate && [date compare:latestExpirationDate] != NSOrderedDescending) {
        return YES;
    }
    return NO;
}

@end
