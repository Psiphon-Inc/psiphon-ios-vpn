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

NSString *const kIAPSKProductsRequestDidReceiveResponse = @"kIAPSKProductsRequestDidReceiveResponse";
NSString *const kIAPSKProductsRequestDidFailWithError = @"kIAPSKProductsRequestDidFailWithError";
NSString *const kIAPSKRequestRequestDidFinish = @"kIAPSKRequestRequestDidFinish";
NSString *const kIAPSKPaymentQueueRestoreCompletedTransactionsFailedWithError = @"kIAPSKPaymentQueueRestoreCompletedTransactionsFailedWithError";
NSString *const kIAPSKPaymentQueuePaymentQueueRestoreCompletedTransactionsFinished = @"kIAPSKPaymentQueuePaymentQueueRestoreCompletedTransactionsFinished";
NSString *const kIAPSKPaymentTransactionStatePurchasing = @"kIAPSKPaymentTransactionStatePurchasing";
NSString *const kIAPSSKPaymentTransactionStateDeferred = @"kIAPSSKPaymentTransactionStateDeferred";
NSString *const kIAPSKPaymentTransactionStateFailed = @"kIAPSKPaymentTransactionStateFailed";
NSString *const kIAPSKPaymentTransactionStatePurchased = @"kIAPSKPaymentTransactionStatePurchased";
NSString *const kIAPSKPaymentTransactionStateRestored = @"kIAPSKPaymentTransactionStateRestored";


@interface IAPStoreHelper()<SKPaymentTransactionObserver,SKProductsRequestDelegate>
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

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    [[NSNotificationCenter defaultCenter] postNotificationName:kIAPSKPaymentQueueRestoreCompletedTransactionsFailedWithError object:error];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    [[NSNotificationCenter defaultCenter] postNotificationName:kIAPSKPaymentQueuePaymentQueueRestoreCompletedTransactionsFinished object:nil];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
                
            case SKPaymentTransactionStatePurchasing: {
                [[NSNotificationCenter defaultCenter] postNotificationName:kIAPSKPaymentTransactionStatePurchasing object:nil];
                break;
            }
            case SKPaymentTransactionStateDeferred:{
                [[NSNotificationCenter defaultCenter] postNotificationName:kIAPSSKPaymentTransactionStateDeferred object:nil];
                break;
            }
            case SKPaymentTransactionStateFailed:{
                [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                [[NSNotificationCenter defaultCenter] postNotificationName:kIAPSKPaymentTransactionStateFailed object:nil];
                break;
            }
            case SKPaymentTransactionStatePurchased:{
                [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                [[NSNotificationCenter defaultCenter] postNotificationName:kIAPSKPaymentTransactionStatePurchased object:nil];
                break;
            }
            case SKPaymentTransactionStateRestored: {
                [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                [[NSNotificationCenter defaultCenter] postNotificationName:kIAPSKPaymentTransactionStateRestored object:nil];
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
    [[NSNotificationCenter defaultCenter]postNotificationName:kIAPSKRequestRequestDidFinish object:nil];
}

- (void)buyProduct:(SKProduct *)product {
    SKPayment * payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
}

@end
