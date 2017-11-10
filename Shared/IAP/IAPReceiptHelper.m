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

#import "IAPReceiptHelper.h"
#import <StoreKit/StoreKit.h>


@implementation IAPReceiptHelper {
   NSInteger _cachedAppReceipFileSize;
   RMAppReceipt *_cachedAppReceipt;
}

+ (instancetype)sharedInstance {
    static IAPReceiptHelper *iapReceiptHelper = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iapReceiptHelper = [[IAPReceiptHelper alloc]init];
        NSURL *plistURL = [[NSBundle mainBundle] URLForResource:@"productIDs" withExtension:@"plist"];
        [RMAppReceipt setAppleRootCertificateURL: [[NSBundle mainBundle] URLForResource:@"AppleIncRootCertificate" withExtension:@"cer"]];
        iapReceiptHelper.bundledProductIDS = [NSArray arrayWithContentsOfURL:plistURL];
    });
    return iapReceiptHelper;
}

- (id) init {
    self = [super init];
    if (self) {
        _cachedAppReceipt = nil;
        _cachedAppReceipFileSize = 0;
    }
    return self;
}

+ (void) terminateForInvalidReceipt {
    SKTerminateForInvalidReceipt();
}

- (RMAppReceipt *)appReceipt {
    NSURL *URL = [NSBundle mainBundle].appStoreReceiptURL;
    NSNumber* theSize;
    NSInteger fileSize = 0;

    if ([URL getResourceValue:&theSize forKey:NSURLFileSizeKey error:nil]) {
        fileSize = [theSize integerValue];
        if (fileSize != _cachedAppReceipFileSize) {
            _cachedAppReceipt  =  [RMAppReceipt bundleReceipt];
            _cachedAppReceipFileSize = fileSize;
        }
    }
    return _cachedAppReceipt;
}

- (BOOL) verifyReceipt  {
    RMAppReceipt* receipt = [self appReceipt];

    if (!receipt) {
        return NO;
    }

    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    if (![receipt.bundleIdentifier isEqualToString:bundleIdentifier]) {
        return NO;
    }

    // Leave build number check out because receipt may not get refreshed automatically
    // when a new version is installed.
    /*
     NSString *applicationVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
     if (![receipt.appVersion isEqualToString:applicationVersion]) {
     return NO;
     }
     */

    if (![receipt verifyReceiptHash]) {
        return NO;
    }

    return YES;
}

- (BOOL) hasActiveSubscriptionForDate:(NSDate*)date {
    // Assuming the products are subscriptions only check all product IDs in
    // the receipt against the bundled products list and determine if
    // we have at least one active subscription for current date.
    if(![self appReceipt]) {
        return NO;
    }


#if !DEBUG
    // Allow some tolerance IRL.
    date = [date dateByAddingTimeInterval:-SUBSCRIPTION_CHECK_GRACE_PERIOD_INTERVAL];
#endif

    BOOL hasSubscription = NO;

    for (NSString* productID in self.bundledProductIDS) {
        NSDate *subscriptionExpirationDate = [[self appReceipt] expirationDateForProduct:productID];
        hasSubscription = (subscriptionExpirationDate && [date compare:subscriptionExpirationDate] != NSOrderedDescending);
        if (hasSubscription) {
            return YES;
        }
    }

    return NO;
}

@end

