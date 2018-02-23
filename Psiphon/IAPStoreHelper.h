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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <StoreKit/StoreKit.h>

FOUNDATION_EXPORT NSNotificationName const IAPSKProductsRequestDidReceiveResponseNotification;
FOUNDATION_EXPORT NSNotificationName const IAPSKProductsRequestDidFailWithErrorNotification;
FOUNDATION_EXPORT NSNotificationName const IAPSKRequestRequestDidFinishNotification;
FOUNDATION_EXPORT NSNotificationName const IAPHelperUpdatedSubscriptionDictionaryNotification;

@interface IAPStoreHelper : NSObject

@property (nonatomic,strong) NSArray *storeProducts;
@property (nonatomic,strong) NSArray *bundledProductIDS;

+ (instancetype)sharedInstance;
+ (BOOL)canMakePayments;
- (void)restoreSubscriptions;
- (void)refreshReceipt;
- (void)startProductsRequest;
- (void)buyProduct:(SKProduct*)product;

#pragma mark - Subscription

+ (NSDictionary*)subscriptionDictionary;

+ (void)storeSubscriptionDictionary:(NSDictionary*)dict;

/**
 * Asynchronously checks on background thread if there active subscription against current time.
 * @param block Block executed on the main thread's default queue, and passed in subscription check result as parameter.
 */
+ (void)hasActiveSubscriptionForNowOnBlock:(void (^)(BOOL isActive))block;

/**
 * Checks whether there is active subscription against current time.
 * @return TRUE if subscription is active, FALSE otherwise.
 */
+ (BOOL)hasActiveSubscriptionForNow;

/**
 * Checks whether there is active subscription given date.
 * @param date Date to compare the authorization token expiration to.
 * @return TRUE if subscription is active, FALSE otherwise.
 */
+ (BOOL)hasActiveSubscriptionForDate:(NSDate*)date;

/**
 * Checks whether there is active subscription given date.
 * If expiryDate is not nil and the method return TRUE, expiryDate will point to NSDate with expiration time.
 * @param date Date to compare the authorization token expiration to.
 * @param expiryDate If not nil, and the return value is TRUE, it will point to NSDate with expiration time.
 * @return TRUE if subscription is active, FALSE otherwise.
 */
+ (BOOL)hasActiveSubscriptionForDate:(NSDate *)date getExpiryDate:(NSDate **)expiryDate;

+ (BOOL)shouldUpdateSubscriptionDictionary:(NSDictionary*)subscriptionDict;

@end
