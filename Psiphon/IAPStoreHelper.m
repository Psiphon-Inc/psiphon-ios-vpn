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
#import "RMAppReceipt.h"
#import "IAPSubscriptionHelper.h"


NSString *const kIAPSKProductsRequestDidReceiveResponse = @"kIAPSKProductsRequestDidReceiveResponse";
NSString *const kIAPSKProductsRequestDidFailWithError = @"kIAPSKProductsRequestDidFailWithError";
NSString *const kIAPSKRequestRequestDidFinish = @"kIAPSKRequestRequestDidFinish";
NSString *const kIAPHelperUpdatedSubscriptionDictionary = @"kIAPHelperUpdatedSubscriptionDictionary";

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

- (void) updateSubscriptionDictionaryFromLocalReceipt {

    NSDictionary *subscriptionDict = [[IAPSubscriptionHelper class] sharedSubscriptionDictionary];

    if(![[IAPSubscriptionHelper class] shouldUpdateSubscriptionDictinary:subscriptionDict withPendingRenewalInfoCheck:NO]) {
        return;
    }

    @autoreleasepool {
        RMAppReceipt *receipt  =  [RMAppReceipt bundleReceipt];
        if(receipt && [receipt verifyReceiptHash]) {
            NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
            if ([bundleIdentifier containsString:receipt.bundleIdentifier]) {
                subscriptionDict = [NSDictionary dictionaryWithDictionary:receipt.inAppSubscriptions];
            }
        }
        receipt = nil;
    }

    [[IAPSubscriptionHelper class] storesharedSubscriptionDisctionary:subscriptionDict];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIAPHelperUpdatedSubscriptionDictionary object:nil];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    [self updateSubscriptionDictionaryFromLocalReceipt];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    [self updateSubscriptionDictionaryFromLocalReceipt];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
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
                [self updateSubscriptionDictionaryFromLocalReceipt];
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
    [[NSNotificationCenter defaultCenter]postNotificationName:kIAPSKProductsRequestDidReceiveResponse object:nil];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    [[NSNotificationCenter defaultCenter]postNotificationName:kIAPSKProductsRequestDidFailWithError object:nil];
}

- (void)requestDidFinish:(SKRequest *)request {
    if ([request isKindOfClass:[SKReceiptRefreshRequest class]]) {
        [self updateSubscriptionDictionaryFromLocalReceipt];
    } else {
        [[NSNotificationCenter defaultCenter]postNotificationName:kIAPSKRequestRequestDidFinish object:nil];
    }
}

- (void)buyProduct:(SKProduct *)product {
    SKPayment * payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
}

@end
