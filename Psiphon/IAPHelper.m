#import "IAPHelper.h"

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


@interface IAPHelper()<SKPaymentTransactionObserver,SKProductsRequestDelegate>
@end

@implementation IAPHelper

+ (instancetype)sharedInstance {
    static IAPHelper *iapHelper = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iapHelper = [[IAPHelper alloc]init];
        NSURL *plistURL = [[NSBundle mainBundle] URLForResource:@"productIDs" withExtension:@"plist"];
        [RMAppReceipt setAppleRootCertificateURL: [[NSBundle mainBundle] URLForResource:@"AppleIncRootCertificate" withExtension:@"cer"]];
        iapHelper.bundledProductIDS = [NSArray arrayWithContentsOfURL:plistURL];
        [[SKPaymentQueue defaultQueue]addTransactionObserver:iapHelper];
    });
    return iapHelper;
}

- (RMAppReceipt *)appReceipt {
    return [RMAppReceipt bundleReceipt];
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

- (void) terminateForInvalidReceipt {
    SKTerminateForInvalidReceipt();
}

- (void)startProductsRequest {
    NSSet* subscriptionIDs = [NSSet setWithArray:self.bundledProductIDS];
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc]initWithProductIdentifiers:subscriptionIDs];
    productsRequest.delegate = self;
    [productsRequest start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    self.storeProducts = response.products;
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
        hasSubscription = [[self appReceipt] containsActiveAutoRenewableSubscriptionOfProductIdentifier:productID forDate:date];
        if (hasSubscription) {
            break;
        }
    }
    return hasSubscription;
}

@end
