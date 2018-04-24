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

#import "PsiCashClient.h"
#import "Asserts.h"
#import "CustomIOSAlertView.h"
#import "ExpiringPurchases.h"
#import "Logging.h"
#import "PsiCash.h"
#import "PsiCashAPIModels.h"
#import "PsiCashAuthPackage.h"
#import "PsiCashClientModel.h"
#import "PsiCashErrorTypes.h"
#import "PsiCashSpeedBoostProduct+PsiCashPurchasePrice.h"
#import "ReactiveObjC.h"
#import "NSError+Convenience.h"

@interface PsiCashClient ()

@property (nonatomic, readwrite) RACReplaySubject<PsiCashClientModel *> *clientModelSignal;

@end

NSErrorDomain _Nonnull const PsiCashClientLibraryErrorDomain = @"PsiCashClientLibraryErrorDomain";

@implementation PsiCashClient {
    PsiCash *psiCash;
    ExpiringPurchases *expiringPurchases;
    // Offload work from PsiCashLib's internal completion queue
    dispatch_queue_t completionQueue;

    PsiCashClientModel *model;
}

+ (BOOL)shouldExposePsiCash {
    return YES;
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
        psiCash = [[PsiCash alloc] init]; // TODO: starts the demo-mode client remove when integrating real library
        expiringPurchases = [ExpiringPurchases fromPersistedUserDefaults];
        completionQueue = dispatch_queue_create("com.psiphon3.PsiCashClient.CompletionQueue", DISPATCH_QUEUE_SERIAL);
        model = nil;

        _clientModelSignal = [RACReplaySubject replaySubjectWithCapacity:1];

        [self listenForExpiredPurchases];
    }
    return self;
}

- (void)commitModelStagingArea:(PsiCashClientModelStagingArea *)stagingArea {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.clientModelSignal sendNext:stagingArea.stagedModel];
    });
    model = stagingArea.stagedModel;
}

#pragma mark - ExpiringPurchases

- (void)listenForExpiredPurchases {

    [expiringPurchases.expiredPurchaseStream
      subscribeNext:^(ExpiringPurchase * _Nullable purchase) {

          dispatch_async(self->completionQueue, ^{

              [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"Purchase with id %@ expired", purchase.authorization.ID];

              PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
              [stagingArea updateActivePurchases:[expiringPurchases activePurchases]];
              [self commitModelStagingArea:stagingArea];

          });

      }
      error:^(NSError * _Nullable error) {
          [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"Error while listening for expired purchaes" object:error];
      }
      completed:^{
          [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s unexpected completed signal.", __FUNCTION__];
      }];
}

#pragma mark - Helpers

- (void)displayAlertWithError:(NSError*)e {
    dispatch_async(dispatch_get_main_queue(), ^{
        CustomIOSAlertView *alert = [[CustomIOSAlertView alloc] init];
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 250, 150)];
        l.adjustsFontSizeToFitWidth = YES;
        l.font = [UIFont systemFontOfSize:10.f];
        l.numberOfLines = 0;
        l.text = [e localizedDescription];
        l.textAlignment = NSTextAlignmentCenter;

        alert.containerView = l;
        [alert show];
    });
}

#pragma mark - Refresh Signal

- (void)refreshState {
    RACSignal *refresh = [[self refreshStateFromServer] startWith:[PsiCashRefreshResultModel inProgress]];

    [refresh subscribeNext:^(PsiCashRefreshResultModel *_Nullable r) {
        NSMutableArray<PsiCashPurchasePrice*> *speedBoostPurchasePrices = [[NSMutableArray alloc] init];
        for (PsiCashPurchasePrice *price in r.purchasePrices) {
            if ([price.transactionClass isEqualToString:[PsiCashSpeedBoostProduct purchaseClass]]) {
                [speedBoostPurchasePrices addObject:price];
            } else {
                [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"Ignored PsiCashPurchasePrice with transaction class %@", price.transactionClass];
            }
        }

        PsiCashSpeedBoostProduct *speedBoostProduct = nil;
        if ([speedBoostPurchasePrices count] == 0) {
            [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"No SpeedBoostProductSKUs found in purchase prices array %@", r.purchasePrices];
        } else {
            speedBoostProduct = [PsiCashSpeedBoostProduct productWithPurchasePrices:speedBoostPurchasePrices];
        }

        PsiCashAuthPackage *authPackage = [[PsiCashAuthPackage alloc] initWithValidTokens:r.validTokenTypes];

        PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
        if (r.inProgress) {
            [stagingArea updateAuthPackage:nil];
            [stagingArea updateSpeedBoostProduct:speedBoostProduct];
            [stagingArea updateActivePurchases:[expiringPurchases activePurchases]];
        } else {
            [stagingArea updateAuthPackage:authPackage];
            [stagingArea updateBalanceInNanoPsi:[r.balance unsignedLongLongValue]];
            [stagingArea updateSpeedBoostProduct:speedBoostProduct];
            [stagingArea updateActivePurchases:[expiringPurchases activePurchases]];
        }

        [self commitModelStagingArea:stagingArea];

    } error:^(NSError * _Nullable error) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"Failed to refresh client state" object:error];
        [self displayAlertWithError:error];
    } completed:^{
        [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"Successfully refreshed state"];
    }];
}

- (RACSignal<PsiCashRefreshResultModel*>*)refreshStateFromServer {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber>  _Nonnull subscriber) {
        [psiCash refreshState:@[[PsiCashSpeedBoostProduct purchaseClass]] withCompletion:
         ^(PsiCashRequestStatus status, NSArray * _Nullable validTokenTypes, BOOL isAccount, NSNumber * _Nullable balance, NSArray * _Nullable purchasePrices, NSError * _Nullable error) {
                if (status == kSuccess) {
                    if (isAccount) {
                        PSIAssert(FALSE); // TODO" (post-mvp) handle login flow
                    }
                    dispatch_async(self->completionQueue, ^{
                        [subscriber sendNext:[PsiCashRefreshResultModel successWithValidTokenTypes:validTokenTypes balance:balance andPurchasePrices:purchasePrices]];
                        [subscriber sendCompleted];
                    });
                } else {
                    NSError *e;
                    if (status == kServerError) {
                        e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:status andLocalizedDescription:@"Server error"];
                    } else if (status == kInvalid) {
                        e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:status andLocalizedDescription:@"Invalid response"];
                    } else if (status == kInvalidTokens) {
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

    PsiCashClientModelStagingArea *pendingPurchasesStagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];
    [pendingPurchasesStagingArea updatePendingPurchases:@[sku]];
    [self commitModelStagingArea:pendingPurchasesStagingArea];

    RACSignal *makePurchase = [self makeExpiringPurchaseTransactionForClass:[PsiCashSpeedBoostProduct purchaseClass]
                                                           andDistinguisher:sku.distinguisher
                                                          withExpectedPrice:sku.price];

    [makePurchase subscribeNext:^(PsiCashMakePurchaseResultModel *_Nullable result) {

        PsiCashClientModelStagingArea *stagingArea = [[PsiCashClientModelStagingArea alloc] initWithModel:model];

        if (result.status == kSuccess) {
            Authorization *authorization = [[Authorization alloc] initWithEncodedAuthorization:result.authorization];
            NSError *e = nil;
            if (authorization == nil) {
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:@"Got nil auth token from PsiCash library"];
            }

            if (authorization.accessType != [PsiCashSpeedBoostProduct purchaseClass]) {
                NSString *s = [NSString stringWithFormat:@"Got auth token from PsiCash library with wrong purchase class of %@", authorization.accessType];
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];
            }

            [stagingArea updateBalanceInNanoPsi:[result.balance unsignedLongLongValue]];

            if (e != nil) {
                ExpiringPurchase *purchase = [ExpiringPurchase expiringPurchaseWithProductName:[PsiCashSpeedBoostProduct purchaseClass] SKU:sku expiryDate:result.expiry andAuthorization:authorization];
                [expiringPurchases addExpiringPurchase:purchase];
                [stagingArea updateActivePurchases:[expiringPurchases activePurchases]];
            } else {
                [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"Received invalid purchase result" object:e];
            }
        } else {
            NSError *e = nil;
            if (result.status == kExistingTransaction) {
                // TODO: Ask adam-p about this
                PSIAssert(FALSE);
                // Price, balance and expiry valid
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:@"Error: you are already Speed Boosting."];

                Authorization *authorization = [[Authorization alloc] initWithEncodedAuthorization:result.authorization];
                NSError *e = nil;
                if (authorization == nil) {
                    e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:@"Got nil auth token from PsiCash library"];
                }

                if (authorization.accessType != [PsiCashSpeedBoostProduct purchaseClass]) {
                    NSString *s = [NSString stringWithFormat:@"Got auth token from PsiCash library with wrong purchase class of %@", authorization.accessType];
                    e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];
                }

                if (e != nil) {
                    [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"Received invalid purchase result" object:e];
                }

                PsiCashSpeedBoostProductSKU *purchasedSKU = [PsiCashSpeedBoostProductSKU skuWitDistinguisher:@"todo" withHours:[NSNumber numberWithInt:1] /* TODO */ andPrice:result.price];
                ExpiringPurchase *purchase = [ExpiringPurchase expiringPurchaseWithProductName:[PsiCashSpeedBoostProduct purchaseClass] SKU:purchasedSKU expiryDate:result.expiry andAuthorization:authorization];

                [expiringPurchases addExpiringPurchase:purchase];

                [stagingArea updateBalanceInNanoPsi:[result.balance unsignedLongLongValue]];
                [stagingArea updateActivePurchases:[expiringPurchases activePurchases]];

            } else if (result.status == kInsufficientBalance) {
                NSString *s = [NSString stringWithFormat:@"Insufficient balance for Speed Boost purchase. Your balance: %@, price: %@.", result.balance, result.price];
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];

                [stagingArea updateBalanceInNanoPsi:[result.balance unsignedLongLongValue]];

            } else if (result.status == kTransactionAmountMismatch) {
                NSString *s = [NSString stringWithFormat:@"Error: price of Speed Boost is out of date. You attempted to pay %@, but the cost is now %@.", sku.price, result.price];
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];

                [stagingArea updateBalanceInNanoPsi:[result.balance unsignedLongLongValue]];
                [stagingArea updateSpeedBoostProductSKU:sku withNewPrice:result.price];

            } else if (result.status == kTransactionTypeNotFound) {
                NSString *s = [NSString stringWithFormat:@"Error: Speed Boost product not found. Local products updated. Your app may be out of date. Please check for updates."];
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:s];

                [stagingArea removeSpeedBoostProductSKU:sku];

            } else if (result.status == kInvalidTokens) {
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:@"Invalid Tokens: the app has entered an invalid state. Please reinstall the app to continue using PsiCash."];
            } else if (result.status == kServerError) {
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:@"Server error"];
            } else {
                e = [NSError errorWithDomain:PsiCashClientLibraryErrorDomain code:result.status andLocalizedDescription:@"Invalid or unexpected status code returned from PsiCash library"];
            }

            if (e != nil) {
                [self displayAlertWithError:e];
            }
        }

        [stagingArea updatePendingPurchases:nil];
        [self commitModelStagingArea:stagingArea];

    } error:^(NSError * _Nullable error) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s unexpected error signal.", __FUNCTION__];
    } completed:^{
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s unexpected completed signal.", __FUNCTION__];
    }];
}

- (RACSignal<PsiCashMakePurchaseResultModel*>*)makeExpiringPurchaseTransactionForClass:(NSString*)transactionClass andDistinguisher:(NSString*)distinguisher withExpectedPrice:(NSNumber*)expectedPrice {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber>  _Nonnull subscriber) {
        [psiCash newExpiringPurchaseTransactionForClass:transactionClass
                                      withDistinguisher:distinguisher
                                      withExpectedPrice:expectedPrice
                                         withCompletion:
         ^(PsiCashRequestStatus status, NSNumber * _Nullable price, NSNumber * _Nullable balance, NSDate * _Nullable expiry, NSString * _Nullable authorization, NSError * _Nullable error) {
             dispatch_async(self->completionQueue, ^{
                 [subscriber sendNext:[PsiCashMakePurchaseResultModel successWithStatus:status
                                                                          andPrice:price
                                                                        andBalance:balance
                                                                         andExpiry:expiry
                                                                  andAuthorization:authorization
                                                                          andError:error]];
                 [subscriber sendCompleted];
             });
         }];
        return nil;
    }];
}

@end
