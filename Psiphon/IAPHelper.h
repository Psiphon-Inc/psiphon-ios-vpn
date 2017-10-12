#import <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#import <StoreKit/StoreKit.h>
#import "RMAppReceipt.h"

#define SUBSCRIPTION_CHECK_GRACE_PERIOD_INTERVAL 2 * 60 * 60 * 24  // two days

extern NSString *const kIAPSKProductsRequestDidReceiveResponse;
extern NSString *const kIAPSKProductsRequestDidFailWithError;
extern NSString *const kIAPSKRequestRequestDidFinish;
extern NSString *const kIAPSKPaymentQueueRestoreCompletedTransactionsFailedWithError;
extern NSString *const kIAPSKPaymentQueuePaymentQueueRestoreCompletedTransactionsFinished;
extern NSString *const kIAPSKPaymentTransactionStatePurchasing;
extern NSString *const kIAPSSKPaymentTransactionStateDeferred;
extern NSString *const kIAPSKPaymentTransactionStateFailed;
extern NSString *const kIAPSKPaymentTransactionStatePurchased;
extern NSString *const kIAPSKPaymentTransactionStateRestored;


@interface IAPHelper : NSObject

@property (nonatomic,strong) NSArray *storeProducts;
@property (nonatomic,strong) NSArray *bundledProductIDS;

+ (instancetype)sharedInstance;
+ (BOOL)canMakePayments;
- (void)restoreSubscriptions;
- (void) refreshReceipt;
- (void) terminateForInvalidReceipt;
- (void)startProductsRequest;
- (void)buyProduct:(SKProduct*)product;
- (RMAppReceipt *)appReceipt;
- (BOOL) hasActiveSubscriptionForDate:(NSDate*)date;
- (BOOL) verifyReceipt;
@end
