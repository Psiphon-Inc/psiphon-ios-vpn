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

#import "IAPStoreHelper.h"
#import "PsiphonAppReceipt.h"
#import "SharedConstants.h"
#import "NSDate+Comparator.h"
#import "DispatchUtils.h"
#import "PsiphonDataSharedDB.h"
#import "Nullity.h"
#import "PsiFeedbackLogger.h"


PsiFeedbackLogType const IAPStoreHelperLogType = @"IAPStore";

NSNotificationName const IAPSKProductsRequestDidReceiveResponseNotification = @"IAPSKProductsRequestDidReceiveResponseNotification";
NSNotificationName const IAPSKProductsRequestDidFailWithErrorNotification = @"IAPSKProductsRequestDidFailWithErrorNotification";
NSNotificationName const IAPSKRequestRequestDidFinishNotification = @"IAPSKRequestRequestDidFinishNotification";
NSNotificationName const IAPHelperUpdatedSubscriptionDictionaryNotification = @"IAPHelperUpdatedSubscriptionDictionaryNotification";

/* Subscription purchase state notification */
NSNotificationName const IAPHelperPaymentTransactionUpdateNotification = @"IAPHelperPaymentTransactionUpdateNotification";
NSString * const IAPHelperPaymentTransactionUpdateKey = @"IAPHelperPaymentTransactionUpdateKey";

NSString *const kSubscriptionDictionary = @"kSubscriptionDictionary";

@interface IAPStoreHelper()<SKPaymentTransactionObserver,SKProductsRequestDelegate>
- (void) updateSubscriptionDictionaryFromLocalReceipt;
@end

@implementation IAPStoreHelper

+ (instancetype)sharedInstance {
    static IAPStoreHelper *iapStoreHelper = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iapStoreHelper = [[IAPStoreHelper alloc]init];
        NSURL *plistURL = [[NSBundle mainBundle] URLForResource:@"productIDs" withExtension:@"plist"];
        iapStoreHelper.bundledProductIDS = [NSArray arrayWithContentsOfURL:plistURL];
        [[SKPaymentQueue defaultQueue]addTransactionObserver:iapStoreHelper];
        [iapStoreHelper updateSubscriptionDictionaryFromLocalReceipt];
    });
    return iapStoreHelper;
}

- (void)dealloc {
    [[SKPaymentQueue defaultQueue]removeTransactionObserver:self];
}

+ (BOOL)canMakePayments {
    return [SKPaymentQueue canMakePayments];
}

- (void)restoreSubscriptions {
    [[SKPaymentQueue defaultQueue]restoreCompletedTransactions];
}

- (void)updateSubscriptionDictionaryFromLocalReceipt {

    NSDictionary *subscriptionDict = [[self class] subscriptionDictionary];

    if(![[self class] shouldUpdateSubscriptionDictionary:subscriptionDict]) {
        return;
    }

    @autoreleasepool {
        PsiphonAppReceipt *receipt = [PsiphonAppReceipt bundleReceipt];
        if(receipt) {
            NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];

            if ([bundleIdentifier containsString:receipt.bundleIdentifier]) {
                subscriptionDict = [NSDictionary dictionaryWithDictionary:receipt.inAppSubscriptions];

                // If the receipt contains no purchase data, store the app receipt file size in PsiphonDataSharedDB
                PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

                if (receipt.inAppSubscriptions) {

                    NSNumber *receiptFileSize = receipt.inAppSubscriptions[kAppReceiptFileSize];

                    // If inAppSubscriptions dictionary is missing expiration date or product id,
                    // then this receipt has no transactions, and is empty.
                    if ([Nullity isNil:receipt.inAppSubscriptions[kLatestExpirationDate]] &&
                        [Nullity isEmpty:receipt.inAppSubscriptions[kProductId]]) {

                        [sharedDB setContainerEmptyReceiptFileSize:receiptFileSize];

                        [PsiFeedbackLogger infoWithType:IAPStoreHelperLogType
                                                   json:@{@"event": @"readReceipt",
                                                          @"fileSize": receiptFileSize,
                                                          @"expiry": NSNull.null}];

                    } else {
                        // The receipt contains purchase data, reset value in the shared DB.
                        [sharedDB setContainerEmptyReceiptFileSize:nil];

                        // Store the expiry date (for extension's use).
                        NSDate *expiry = receipt.inAppSubscriptions[kLatestExpirationDate];
                        [sharedDB setContainerLastSubscriptionReceiptExpiryDate:expiry];

                        [PsiFeedbackLogger infoWithType:IAPStoreHelperLogType
                                                   json:@{@"event": @"readReceipt",
                                                          @"fileSize": receiptFileSize,
                                                          @"expiry": [PsiFeedbackLogger safeValue:expiry]}];
                    }
                }

            }
        }
        receipt = nil;
    }

    [[self class] storeSubscriptionDictionary:subscriptionDict];
    [[NSNotificationCenter defaultCenter] postNotificationName:IAPHelperUpdatedSubscriptionDictionaryNotification object:nil];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    [self updateSubscriptionDictionaryFromLocalReceipt];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    [self updateSubscriptionDictionaryFromLocalReceipt];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {

        // Updates subscription dictionary independent of transaction state.
        // This is to store information about the receipt if it is empty.
        [self updateSubscriptionDictionaryFromLocalReceipt];

        // Sends notification containing updates state of a transaction.
        [[NSNotificationCenter defaultCenter]
          postNotificationName:IAPHelperPaymentTransactionUpdateNotification
                        object:nil
                      userInfo:@{IAPHelperPaymentTransactionUpdateKey : @(transaction.transactionState)}];

        switch (transaction.transactionState) {

            case SKPaymentTransactionStatePurchasing: {
                break;
            }
            case SKPaymentTransactionStateDeferred:{
                break;
            }
            case SKPaymentTransactionStateFailed:{
                [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStatePurchased:{
                [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStateRestored: {
                [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                break;
            }
        }
    }
}

- (void)refreshReceipt {
    SKReceiptRefreshRequest *receiptRefreshRequest = [[SKReceiptRefreshRequest alloc] initWithReceiptProperties:nil];
    receiptRefreshRequest.delegate = self;
    [receiptRefreshRequest start];
}

- (void)startProductsRequest {
    NSSet* subscriptionIDs = [NSSet setWithArray:self.bundledProductIDS];
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc]initWithProductIdentifiers:subscriptionIDs];
    productsRequest.delegate = self;
    [productsRequest start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    // Sort products by price
    NSSortDescriptor *mySortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"price" ascending:YES];
    NSMutableArray *sortArray = [[NSMutableArray alloc] initWithArray:response.products];
    [sortArray sortUsingDescriptors:[NSArray arrayWithObject:mySortDescriptor]];
    self.storeProducts = sortArray;
    [[NSNotificationCenter defaultCenter]postNotificationName:IAPSKProductsRequestDidReceiveResponseNotification object:nil];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    [[NSNotificationCenter defaultCenter]postNotificationName:IAPSKProductsRequestDidFailWithErrorNotification object:nil];
}

- (void)requestDidFinish:(SKRequest *)request {
    if ([request isKindOfClass:[SKReceiptRefreshRequest class]]) {
        [self updateSubscriptionDictionaryFromLocalReceipt];
    } else {
        [[NSNotificationCenter defaultCenter]postNotificationName:IAPSKRequestRequestDidFinishNotification object:nil];
    }
}

- (void)buyProduct:(SKProduct *)product {
    SKPayment * payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
}

+ (BOOL)shouldUpdateSubscriptionDictionary:(NSDictionary*)subscriptionDict {
    // If no receipt - NO
    NSURL *URL = [NSBundle mainBundle].appStoreReceiptURL;
    NSString *path = URL.path;
    const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil];
    if (!exists) {
        [PsiFeedbackLogger infoWithType:IAPStoreHelperLogType
                                   json:@{@"event": @"shouldUpdate",
                                          @"result": @(NO),
                                          @"reason": @"noReceipt"}];
        return NO;
    }

    // There's receipt but no subscriptionDictionary - YES
    if(!subscriptionDict) {
        [PsiFeedbackLogger infoWithType:IAPStoreHelperLogType
                                   json:@{@"event": @"shouldUpdate",
                                         @"result": @(YES),
                                         @"reason": @"noLocalData"}];
        return YES;
    }

    // Receipt file size has changed since last check - YES
    NSNumber* appReceiptFileSize = nil;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:nil];
    NSNumber* dictAppReceiptFileSize = subscriptionDict[kAppReceiptFileSize];
    if ([appReceiptFileSize unsignedIntValue] != [dictAppReceiptFileSize unsignedIntValue]) {

        [PsiFeedbackLogger infoWithType:IAPStoreHelperLogType
                                   json:@{@"event": @"shouldUpdate",
                                         @"result": @(YES),
                                         @"reason": @"fileSizeChange"}];
        return YES;
    }

    // If user has an active subscription for date - NO
    if ([[self class] hasActiveSubscriptionForDate:[NSDate date] inDict:subscriptionDict getExpiryDate:nil]) {
        [PsiFeedbackLogger infoWithType:IAPStoreHelperLogType
                                   json:@{@"event": @"shouldUpdate",
                                         @"result": @(NO),
                                         @"reason": @"subscriptionActive"}];
        return NO;
    }

    return NO;
}

+ (NSDictionary*)subscriptionDictionary {
    return (NSDictionary*)[[NSUserDefaults standardUserDefaults] dictionaryForKey:kSubscriptionDictionary];
}

+ (void)storeSubscriptionDictionary:(NSDictionary*)dict {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:dict forKey:kSubscriptionDictionary];
    [userDefaults synchronize];
}

+ (void)hasActiveSubscriptionForNowOnBlock:(void (^)(BOOL isActive))block {
    dispatch_async_global(^{
        BOOL isActive = [[self class] hasActiveSubscriptionForNow];
        dispatch_async_main(^{
            block(isActive);
        });
    });
}

+ (BOOL)hasActiveSubscriptionForNow {
    return [[self class] hasActiveSubscriptionForDate:[NSDate date]];
}

+ (BOOL)hasActiveSubscriptionForDate:(NSDate*)date {
    return [[self class] hasActiveSubscriptionForDate:date getExpiryDate:nil];
}

+ (BOOL)hasActiveSubscriptionForDate:(NSDate *)date getExpiryDate:(NSDate **)expiryDate {
    NSDictionary* dict = [[self class] subscriptionDictionary];
    return [[self class] hasActiveSubscriptionForDate:date inDict:dict getExpiryDate:expiryDate];
}

+ (BOOL)hasActiveSubscriptionForDate:(NSDate*)date inDict:(NSDictionary*)subscriptionDict getExpiryDate:(NSDate **)expiryDate {
    if(!subscriptionDict) {
        return NO;
    }

    NSDate *latestExpirationDate = subscriptionDict[kLatestExpirationDate];
    if(latestExpirationDate && [date beforeOrEqualTo:latestExpirationDate]) {
        if (expiryDate) {
            (*expiryDate) = [latestExpirationDate copy];
        }
        return YES;
    }
    return NO;
}
@end
