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

#import <PsiCashLib/PsiCash.h>
#import "PsiCashClient.h"
#import "AppDelegate.h"
#import "Asserts.h"
#import "Authorization.h"
#import "CustomIOSAlertView.h"
#import "Logging.h"
#import "Notifier.h"
#import "PsiCashAPIModels.h"
#import "PsiCashAuthPackage.h"
#import "PsiCashClientModel.h"
#import "PsiCashErrorTypes.h"
#import "PsiCashSpeedBoostProduct+PsiCashPurchasePrice.h"
#import "PsiphonDataSharedDB.h"
#import "RACSignal+Operations2.h"
#import "ReactiveObjC.h"
#import "SharedConstants.h"
#import "NSError+Convenience.h"
#import "VPNManager.h"

@interface PsiCashClient ()

@property (nonatomic, readwrite) RACReplaySubject<PsiCashClientModel *> *clientModelSignal;

@end

NSErrorDomain _Nonnull const PsiCashClientLibraryErrorDomain = @"PsiCashClientLibraryErrorDomain";

@implementation PsiCashClient {
    PsiCash *psiCash;

    // Offload work from PsiCashLib's internal completion queue
    dispatch_queue_t completionQueue;

    PsiCashClientModel *model;
    PsiphonDataSharedDB *sharedDB;

    VPNManager *vpnManager;
    RACDisposable *tunnelStatusDisposable;
    RACDisposable *refreshDisposable;
    RACDisposable *purchaseDisposable;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        psiCash = [[PsiCash alloc] init];
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        // TODO: (1.0) notify the user about any purchases that expired while the app was backgrounded
        NSArray <PsiCashPurchase*>* expiredPurchases = [psiCash expirePurchases];
        if (expiredPurchases.count > 0) {
            [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"Purchases expired: %@", expiredPurchases];
        }

        completionQueue = dispatch_queue_create("com.psiphon3.PsiCashClient.CompletionQueue", DISPATCH_QUEUE_SERIAL);

        _clientModelSignal = [RACReplaySubject replaySubjectWithCapacity:1];

        vpnManager = [VPNManager sharedInstance];
    }
    return self;
}

- (NSURL*)modifiedHomePageURL:(NSURL*)url {
    NSString *modifiedURL = nil;

    NSError *e = [psiCash modifyLandingPage:[url absoluteString] modifiedURL:&modifiedURL];
    if (e!= nil) {
        // TODO: should never happen because landing page is hardcoded above
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"error constructing PsiCash landing page URL" object:e];
        return url;
    }

    return [NSURL URLWithString:modifiedURL];
}

- (void)scheduleStateRefresh {
    __weak PsiCashClient *weakSelf = self;
    [tunnelStatusDisposable dispose];

    // Observe VPN status for updating UI state
    tunnelStatusDisposable = [vpnManager.lastTunnelStatus
                              subscribeNext:^(NSNumber *statusObject) {
                                  VPNStatus s = (VPNStatus) [statusObject integerValue];

                                  if (s == VPNStatusConnected) {
                                      [weakSelf refreshState];
                                  } else {
                                      [refreshDisposable dispose]; // cancel the request in flight
                                      [weakSelf refreshStateFromCache];
                                  }
                              }];
}

#pragma mark - Helpers

- (void)commitModelStagingArea:(PsiCashClientModelStagingArea *)stagingArea {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.clientModelSignal sendNext:stagingArea.stagedModel];
    });
    model = stagingArea.stagedModel;
}

- (void)displayAlertWithMessage:(NSString*)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        CustomIOSAlertView *alert = [[CustomIOSAlertView alloc] init];
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 250, 150)];
        l.adjustsFontSizeToFitWidth = YES;
        l.font = [UIFont systemFontOfSize:12.f];
        l.numberOfLines = 0;
        l.text = msg;
        l.textAlignment = NSTextAlignmentCenter;

        alert.containerView = l;
        [alert show];
    });
}

/**
 * Hardcode SpeedBoost product to only 1h option for PsiCash 1.0
 */
- (NSDictionary<NSString*,NSArray<NSString*>*>*)targetProducts {
    return @{[PsiCashSpeedBoostProduct purchaseClass]: @[@"1hr"]};
}

/**
 * Helper function to parse an array of PsiCashPurchasePrice objects
 * into a more completely typed PsiCashSpeedBoostProduct object.
 */
- (PsiCashSpeedBoostProduct*)speedBoostProductFromPurchasePrices:(NSArray<PsiCashPurchasePrice*>*)purchasePrices withTargetProducts:(NSDictionary<NSString*,NSArray<NSString*>*>*)targets {
    NSMutableArray<PsiCashPurchasePrice*> *speedBoostPurchasePrices = [[NSMutableArray alloc] init];
    NSArray <NSString*>* targetDistinguishersForSpeedBoost = nil;
    if (targets != nil) {
        targetDistinguishersForSpeedBoost = [targets objectForKey:[PsiCashSpeedBoostProduct purchaseClass]];
    }

    for (PsiCashPurchasePrice *price in purchasePrices) {
        if ([price.transactionClass isEqualToString:[PsiCashSpeedBoostProduct purchaseClass]]) {
            if (targetDistinguishersForSpeedBoost == nil
                || (targetDistinguishersForSpeedBoost != nil && [targetDistinguishersForSpeedBoost containsObject:price.distinguisher])) {
                [speedBoostPurchasePrices addObject:price];
            }
        } else {
            [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"Ignored PsiCashPurchasePrice with transaction class %@", price.transactionClass];
        }
    }

    PsiCashSpeedBoostProduct *speedBoostProduct = nil;
    if ([speedBoostPurchasePrices count] == 0) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"No SpeedBoostProductSKUs found in purchase prices array %@", purchasePrices];
    } else {
        speedBoostProduct = [PsiCashSpeedBoostProduct productWithPurchasePrices:speedBoostPurchasePrices];
    }

    return speedBoostProduct;
}

- (void)updateContainerAuthTokens {
    [sharedDB setContainerAuthorizations:[self getValidAuthorizations]];
}

- (NSSet<Authorization*>*)getValidAuthorizations {
    NSMutableSet <Authorization*>*validAuthorizations = [[NSMutableSet alloc] init];

    NSArray <PsiCashPurchase*>* purchases = [psiCash purchases];
    for (PsiCashPurchase *purchase in purchases) {
        if ([purchase.transactionClass isEqualToString:[PsiCashSpeedBoostProduct purchaseClass]]) {
            [validAuthorizations addObject:[[Authorization alloc] initWithEncodedAuthorization:purchase.authorization]];
        }
    }

    return validAuthorizations;
}

#pragma mark - Authorization expiries

// See comment in header
- (void)authorizationsMarkedExpired {
    PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
    [stagingArea updateActivePurchases:[self getActivePurchases]];
    [self commitModelStagingArea:stagingArea];
}

/**
 * Returns the set of active purchases from the PsiCash library subtracted by the set
 * of purchases marked as expired by the extension. This handles the scenario where
 * the server has decided a purchase is expired before the library. In this scenario
 * the server should be treated as the ultimate source of truth and these expired
 * purchases will be removed from the library.
 *
 * @return Returns {setActivePurchaseFromLib | x is not marked expired by the extension}
 */
- (NSArray<PsiCashPurchase*>*)getActivePurchases {
    NSMutableArray <PsiCashPurchase*>* purchases = [[NSMutableArray alloc] initWithArray:[[psiCash purchases] copy]];
    NSSet<NSString *> *markedAuthIDs = [sharedDB getMarkedExpiredAuthorizationIDs];
    NSMutableArray *purchasesToRemove = [[NSMutableArray alloc] init];

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PsiCashPurchase *evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        Authorization *auth = [[Authorization alloc] initWithEncodedAuthorization:evaluatedObject.authorization];
        if ([markedAuthIDs containsObject:auth.ID]) {
            [purchasesToRemove addObject:auth.ID];
            return FALSE;
        }
        return TRUE;
    }];
    [purchases filterUsingPredicate:predicate];

    // Remove purchases indicated as expired by the Psiphon server, but not yet by the PsiCash lib.
    // This will occur if the local clock is out of sync with that of the PsiCash server.
    [psiCash removePurchases:purchasesToRemove];

    return purchases;
}

#pragma mark - Cached Refresh

- (void)refreshStateFromCache {
    [self updateContainerAuthTokens];
    PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
    [stagingArea updateBalance:psiCash.balance];
    [stagingArea updateActivePurchases:[self getActivePurchases]];
    [stagingArea updateAuthPackage:[[PsiCashAuthPackage alloc] initWithValidTokens:psiCash.validTokenTypes]];
    [stagingArea updateSpeedBoostProduct:[self speedBoostProductFromPurchasePrices:psiCash.purchasePrices withTargetProducts:[self targetProducts]]];
    [stagingArea updateRefreshPending:NO];
    [self commitModelStagingArea:stagingArea];
}

#pragma mark - Refresh Signal

- (void)refreshState {
    [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"refreshing state"];

#if DEBUG
    const int networkRetryCount = 3;
#else
    const int networkRetryCount = 6;
#endif

    [refreshDisposable dispose];

    RACSignal *refresh = [[[[self refreshStateFromServer] retryWhen:^RACSignal * _Nonnull(RACSignal * _Nonnull errors) {
        return [[errors
                 zipWith:[RACSignal rangeStartFrom:1 count:networkRetryCount]]
                flattenMap:^RACSignal *(RACTwoTuple<NSError *, NSNumber *> *retryCountTuple) {

                    // Emits the error on the last retry.
                    if ([retryCountTuple.second integerValue] == networkRetryCount) {
                        return [RACSignal error:retryCountTuple.first];
                    }
                    // Exponential backoff.
                    return [RACSignal timer:pow(4, [retryCountTuple.second integerValue])];
                }];
    }] catch:^RACSignal * _Nonnull(NSError * _Nonnull error) {
        // Else re-emit the error.
        return [RACSignal error:error];
    }] startWith:[PsiCashRefreshResultModel inProgress]];

    refreshDisposable = [refresh subscribeNext:^(PsiCashRefreshResultModel *_Nullable r) {

        PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
        if (r.inProgress) {
            [stagingArea updateRefreshPending:YES];
            [stagingArea updateActivePurchases:[self getActivePurchases]];
            [self commitModelStagingArea:stagingArea];
            // Do nothing or refresh from lib?
        } else {
            PsiCashAuthPackage *authPackage = [[PsiCashAuthPackage alloc] initWithValidTokens:r.validTokenTypes];
            [stagingArea updateAuthPackage:authPackage];
            [stagingArea updateBalance:r.balance];
            PsiCashSpeedBoostProduct *speedBoostProduct = [self speedBoostProductFromPurchasePrices:r.purchasePrices withTargetProducts:[self targetProducts]];
            [stagingArea updateSpeedBoostProduct:speedBoostProduct];
            [stagingArea updateActivePurchases:[self getActivePurchases]];
            [stagingArea updateRefreshPending:NO];
            [self commitModelStagingArea:stagingArea];
        }

    } error:^(NSError * _Nullable error) {

        PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
        [stagingArea updateRefreshPending:NO];
        [self commitModelStagingArea:stagingArea];

        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s failed to refresh state %@", __FUNCTION__, error.localizedDescription];
        [self displayAlertWithMessage:NSLocalizedStringWithDefaultValue(@"PSICASH_REFRESH_STATE_FAILED_MESSAGE_TEXT", nil, [NSBundle mainBundle], @"Failed to update PsiCash state", @"Alert error message informing user that the app failed to retrieve their PsiCash information from the server")];
    } completed:^{
        [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"refreshed state"];
    }];
}

- (RACSignal<PsiCashRefreshResultModel*>*)refreshStateFromServer {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber>  _Nonnull subscriber) {
        [psiCash refreshState:@[[PsiCashSpeedBoostProduct purchaseClass]] withCompletion:
         ^(PsiCashStatus status, NSArray * _Nullable validTokenTypes, BOOL isAccount, NSNumber * _Nullable balance, NSArray * _Nullable purchasePrices, NSError * _Nullable error) {
                if (error != nil) {
                    // If error non-nil, the request failed utterly and no other params are valid.
                    dispatch_async(self->completionQueue, ^{
                        [subscriber sendError:error];
                    });
                } else if (status == PsiCashStatus_Success) {
                    if (isAccount) {
                        PSIAssert(FALSE); // TODO: (post-MVP) handle login flow
                    }
                    dispatch_async(self->completionQueue, ^{
                        [subscriber sendNext:[PsiCashRefreshResultModel successWithValidTokenTypes:validTokenTypes balance:balance andPurchasePrices:purchasePrices]];
                        [subscriber sendCompleted];
                    });
                } else {
                    NSError *e;
                    if (status == PsiCashStatus_ServerError) {
                        e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:status andLocalizedDescription:@"Server error"];
                    } else if (status == PsiCashStatus_Invalid) {
                        e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:status andLocalizedDescription:@"Invalid response"];
                    } else if (status == PsiCashStatus_InvalidTokens) {
                        e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:status andLocalizedDescription:@"Invalid Tokens: the app has entered an invalid state. Please reinstall the app to continue using PsiCash."];
                    } else {
                        e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:status andLocalizedDescription:@"Invalid or unexpected status code returned from PsiCash library"];
                    }
                    dispatch_async(self->completionQueue, ^{
                        [subscriber sendError:e];
                    });
                }
         }];
        return nil;
    }];
}

#pragma mark - Purchase Signal

- (void)purchaseSpeedBoostProduct:(PsiCashSpeedBoostProductSKU*)sku {
    [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"%s attempting to purchase %@", __FUNCTION__, [sku json]];

    [purchaseDisposable dispose];

    PsiCashClientModelStagingArea *pendingPurchasesStagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
    [pendingPurchasesStagingArea updatePendingPurchases:@[sku]];
    [self commitModelStagingArea:pendingPurchasesStagingArea];

    RACSignal *makePurchase = [self makeExpiringPurchaseTransactionForClass:[PsiCashSpeedBoostProduct purchaseClass]
                                                           andDistinguisher:sku.distinguisher
                                                          withExpectedPrice:sku.price];

    purchaseDisposable = [makePurchase subscribeNext:^(PsiCashMakePurchaseResultModel *_Nullable result) {

        PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];

        if (result.status == PsiCashStatus_Success) {
            Authorization *authorization = [[Authorization alloc] initWithEncodedAuthorization:result.authorization];
            NSError *e = nil;

            if (authorization == nil) {
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:@"Got nil auth token from PsiCash library"];
            }

            if (![authorization.accessType isEqualToString:[PsiCashSpeedBoostProduct purchaseClass]] ) {
                NSString *s = [NSString stringWithFormat:@"Got auth token from PsiCash library with wrong purchase class of %@", authorization.accessType];
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];
            }

            [self updateContainerAuthTokens];
            dispatch_async(dispatch_get_main_queue(), ^{
                // Ensure homepage is shown when extension reconnects with new auth token
                [AppDelegate sharedAppDelegate].shownLandingPageForCurrentSession = FALSE;
            });
            [[Notifier sharedInstance] post:NotifierUpdatedAuthorizations completionHandler:^(BOOL success) {
                // Do nothing.
            }];

            [stagingArea updateBalance:result.balance];

            if (e != nil) {
                [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"Received invalid purchase result" object:e];
            } else {
                [stagingArea updateActivePurchases:[self getActivePurchases]];
            }
        } else {
            NSError *e = nil;
            if (result.status == PsiCashStatus_ExistingTransaction) {
                // TODO: (1.0) retrieve existing transaction
                // Price, balance and expiry valid
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_PURCHASE_FAILED_ALREADY_ACTIVE_PURCHASE", nil, [NSBundle mainBundle], @"Error: you already have an active Speed Boost purchase.", @"Alert error message informing user that their Speed Boost purchase request failed because they already have an active Speed Boost purchase")];

                [stagingArea updateBalance:result.balance];
                [stagingArea updateActivePurchases:[self getActivePurchases]];
            } else if (result.status == PsiCashStatus_InsufficientBalance) {
                NSString *s = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_PURCHASE_FAILED_INSUFFICIENT_FUNDS", nil, [NSBundle mainBundle], @"Insufficient balance for Speed Boost purchase. Price:", @"Alert error message informing user that their Speed Boost purchase request failed because they have an insufficient balance. Required price will be appended after the colon.");
                s = [s stringByAppendingString:[NSString stringWithFormat:@" %@", [PsiCashClientModel formattedBalance:result.balance]]];
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];

                [stagingArea updateBalance:result.balance];

            } else if (result.status == PsiCashStatus_TransactionAmountMismatch) {
                NSString *s = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_PURCHASE_FAILED_PRICE_OUT_OF_DATE", nil, [NSBundle mainBundle], @"Error: price of Speed Boost is out of date. Price:", @"Alert error message informing user that their Speed Boost purchase request failed because they tried to make the purchase with an out of date product price. Updated price will be appended after the colon.");
                s = [s stringByAppendingString:[NSString stringWithFormat:@" %@", [PsiCashClientModel formattedBalance:result.price]]];
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];

                [stagingArea updateBalance:result.balance];
                [stagingArea updateSpeedBoostProductSKU:sku withNewPrice:result.price];

            } else if (result.status == PsiCashStatus_TransactionTypeNotFound) {
                NSString *s = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_PURCHASE_FAILED_PRODUCT_NOT_FOUND", nil, [NSBundle mainBundle], @"Error: Speed Boost product not found. Local products updated. Your app may be out of date. Please check for updates.", @"Alert error message informing user that their Speed Boost purchase request failed because they attempted to buy a product that is no longer available and that they should try updating or reinstalling the app");
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];

                [stagingArea removeSpeedBoostProductSKU:sku];

            } else if (result.status == PsiCashStatus_InvalidTokens) {
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_PURCHASE_FAILED_INVALID_TOKENS", nil, [NSBundle mainBundle], @"Invalid Tokens: the app has entered an invalid state. Please reinstall the app to continue using PsiCash.", @"Alert error message informing user that their Speed Boost purchase request failed because their app has entered an invalid state and that they should try updating or reinstalling the app")];
            } else if (result.status == PsiCashStatus_ServerError) {
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_PURCHASE_FAILED_SERVER_ERROR", nil, [NSBundle mainBundle], @"Server error. Please try again in a few minutes.", @"Alert error message informing user that their Speed Boost purchase request failed due to a server error and that they should try again in a few minutes")];
            } else {
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_PURCHASE_FAILED_UNEXPECTED_CODE", nil, [NSBundle mainBundle], @"Invalid or unexpected status code returned from PsiCash library.", @"Alert error message informing user that their Speed Boost purchase request failed because of an unknown error")];
            }

            if (e != nil) {
                [self displayAlertWithMessage:e.localizedDescription];
                [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s failed to purchase Speed Boost %@", __FUNCTION__, e.localizedDescription];
            }
        }

        [stagingArea updatePendingPurchases:nil];
        [self commitModelStagingArea:stagingArea];
    } error:^(NSError * _Nullable error) {
        PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
        [stagingArea updatePendingPurchases:nil];
        [self commitModelStagingArea:stagingArea];

        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s failed to purchase Speed Boost %@", __FUNCTION__, error.localizedDescription];
        [self displayAlertWithMessage:NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_PURCHASE_FAILED_MESSAGE_TEXT", nil, [NSBundle mainBundle], @"Purchase failed, please try again in a few minutes.", @"Alert message informing user that their Speed Boost purchase attempt unexpectedly failed and that they should try again in a few minutes.")];
    } completed:^{
        [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"%s successfully purchased %@", __FUNCTION__, [sku json]];
    }];
}

- (RACSignal<PsiCashMakePurchaseResultModel*>*)makeExpiringPurchaseTransactionForClass:(NSString*)transactionClass andDistinguisher:(NSString*)distinguisher withExpectedPrice:(NSNumber*)expectedPrice {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber>  _Nonnull subscriber) {
        [psiCash newExpiringPurchaseTransactionForClass:transactionClass
                                      withDistinguisher:distinguisher
                                      withExpectedPrice:expectedPrice
                                         withCompletion:
         ^(PsiCashStatus status, NSNumber * _Nullable price, NSNumber * _Nullable balance, NSDate * _Nullable expiry, NSString*_Nullable transactionID, NSString * _Nullable authorization, NSError * _Nullable error) {
             dispatch_async(self->completionQueue, ^{
                 if (error != nil) {
                     // If error non-nil, the request failed utterly and no other params are valid.
                     [subscriber sendError:error];
                 } else {
                     [subscriber sendNext:[PsiCashMakePurchaseResultModel successWithStatus:status
                                                                                   andPrice:price
                                                                                 andBalance:balance
                                                                                  andExpiry:expiry
                                                                           andAuthorization:authorization
                                                                                   andError:error]];
                     [subscriber sendCompleted];
                 }
             });
         }];
        return nil;
    }];
}

@end
