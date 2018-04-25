/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "PsiCash.h"
#import "Logging.h"
#import "psicash_api.hpp"
#import "AuthorizationToken.h"

NSString * const ERROR_DOMAIN = @"PsiCashLibErrorDomain";
int const DEFAULT_ERROR_CODE = -1;

@implementation NSError (NSErrorExt)

+ (NSError *)errorWrapping:(NSError*)error withMessage:(NSString*)message fromFunction:(const char*)funcname
{
    NSString *desc = [NSString stringWithFormat:@"PsiCashLib:: %s: %@", funcname, message];
    return [NSError errorWithDomain:ERROR_DOMAIN
                               code:DEFAULT_ERROR_CODE
                           userInfo:@{NSLocalizedDescriptionKey: desc,
                                      NSUnderlyingErrorKey: error}];
}

+ (NSError *)errorWithMessage:(NSString*)message fromFunction:(const char*)funcname
{
    NSString *desc = [NSString stringWithFormat:@"PsiCashLib:: %s: %@", funcname, message];
    return [NSError errorWithDomain:ERROR_DOMAIN
                               code:DEFAULT_ERROR_CODE
                           userInfo:@{NSLocalizedDescriptionKey: desc}];
}

@end

#pragma mark - c helpers

int64_t randomDelay() {
    return rand() % 5 + 3;
}

#pragma mark - PsiCashPurchasePrice

@implementation PsiCashPurchasePrice
- (id)initWithPrice:(NSNumber*_Nonnull)price
   andDistinguisher:(NSString*_Nonnull)distinguisher
andTransactionClass:(NSString*_Nonnull)transactionClass {
    self = [super init];

    if (self) {
        self.price = price;
        self.distinguisher = distinguisher;
        self.transactionClass = transactionClass;
    }

    return self;
}

+ (PsiCashPurchasePrice*)speedBoostWithNumHours:(UInt64)hours {
    return [[PsiCashPurchasePrice alloc] initWithPrice:[NSNumber numberWithLongLong:1000000000000 * hours]
                                      andDistinguisher:[NSString stringWithFormat:@"%lluh", hours]
                                   andTransactionClass:@"speed-boost"];
}

+ (NSArray<PsiCashPurchasePrice*>*)speedBoostPurchasePrices {
    return @[[PsiCashPurchasePrice speedBoostWithNumHours:1],
             [PsiCashPurchasePrice speedBoostWithNumHours:2],
             [PsiCashPurchasePrice speedBoostWithNumHours:3],
             [PsiCashPurchasePrice speedBoostWithNumHours:4],
             [PsiCashPurchasePrice speedBoostWithNumHours:5],
             [PsiCashPurchasePrice speedBoostWithNumHours:6],
             [PsiCashPurchasePrice speedBoostWithNumHours:7],
             [PsiCashPurchasePrice speedBoostWithNumHours:8]];
}

@end

#pragma mark - PsiCash

@implementation PsiCash {
    void *client;
    BOOL alwaysSucceedRefresh;
    BOOL alwaysSucceedPurchase;
}

- (id _Nonnull)init
{
    self = [super init];

    if (self) {
        client = new_client(); // TODO: dealloc
        [self startDemoMode];
        alwaysSucceedRefresh = YES;
        alwaysSucceedPurchase = YES;
    }

    return self;
}

#pragma mark - RefreshState

typedef void (^refreshCompletionHandler) (PsiCashRequestStatus status,
                  NSArray*_Nullable validTokenTypes,
                  BOOL isAccount,
                  NSNumber*_Nullable balance,
                  NSArray*_Nullable purchasePrices,
                  NSError*_Nullable error);

- (void)refreshState:(NSArray*_Nonnull)purchaseClasses
      withCompletion:(void (^_Nonnull)(PsiCashRequestStatus status,
                                       NSArray*_Nullable validTokenTypes,
                                       BOOL isAccount,
                                       NSNumber*_Nullable balance,
                                       NSArray*_Nullable purchasePrices, // of PsiCashPurchasePrice
                                       NSError*_Nullable error))completionHandler {
    LOG_DEBUG(@"%@ starting API request", NSStringFromSelector(_cmd));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(randomDelay() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LOG_DEBUG(@"%@ API request completed", NSStringFromSelector(_cmd));

        PsiCashRequestStatus status = alwaysSucceedRefresh ? kSuccess : [self randomStatusCodeForRefreshState];

        if (status == kSuccess) {
            [self refreshStateSuccess:completionHandler];
        } else if (status == kServerError) {
            [self refreshStateServerError:completionHandler];
        } else if (status == kInvalid) {
            [self refreshStateFailedToObtainValidTrackerTokens:completionHandler];
        } else if (status == kInvalidTokens) {
            [self refreshStateInvalidTokens:completionHandler];
        } else {
            assert(FALSE);
        }
    });
}

- (void)refreshStateSuccess:(refreshCompletionHandler)completionHandler {
    cash_client_balance_t b = get_client_balance(client);
    NSNumber *balance = [NSNumber numberWithUnsignedLongLong:b];
    NSArray *purchasePrices = [PsiCashPurchasePrice speedBoostPurchasePrices];
    NSArray *allTokenTypes = @[@"earner", @"indicator", @"spender"]; // TODO: randomize for testing
    BOOL isAccount = NO; // TODO: (post-mvp) handle login flow
    completionHandler(kSuccess, allTokenTypes, isAccount, balance, purchasePrices, nil);
}

- (void)refreshStateServerError:(refreshCompletionHandler)completionHandler {
    completionHandler(kServerError, nil, NO, nil, nil, nil);
}

- (void)refreshStateFailedToObtainValidTrackerTokens:(refreshCompletionHandler)completionHandler {
    NSError *error = [NSError errorWithMessage:@"failed to obtain valid tracker tokens (a)" fromFunction:__FUNCTION__];
    completionHandler(kInvalid, nil, NO, nil, nil, error);
}

- (void)refreshStateInvalidTokens:(refreshCompletionHandler)completionHandler {
    completionHandler(kInvalidTokens, nil, NO, nil, nil, nil);
}

- (PsiCashRequestStatus)randomStatusCodeForRefreshState {
    int r = rand()%4;

    if (r == 0) {
        return kSuccess;
    } else if (r == 1) {
        return kServerError;
    } else if (r == 2) {
        return kInvalid;
    } else {
        return kInvalidTokens;
    }

    return kSuccess;
}

#pragma mark - NewTransaction

typedef void (^expiringPurchaseCompletionHandler) (PsiCashRequestStatus status,
                                                   NSNumber*_Nullable price,
                                                   NSNumber*_Nullable balance,
                                                   NSDate*_Nullable expiry,
                                                   NSString*_Nullable authorization,
                                                   NSError*_Nullable error);

- (void)newExpiringPurchaseTransactionForClass:(NSString*_Nonnull)transactionClass
                             withDistinguisher:(NSString*_Nonnull)transactionDistinguisher
                             withExpectedPrice:(NSNumber*_Nonnull)expectedPrice
                                withCompletion:(void (^_Nonnull)(PsiCashRequestStatus status,
                                                                 NSNumber*_Nullable price,
                                                                 NSNumber*_Nullable balance,
                                                                 NSDate*_Nullable expiry,
                                                                 NSString*_Nullable authorization,
                                                                 NSError*_Nullable error))completion {
    LOG_DEBUG(@"%@ starting API request", NSStringFromSelector(_cmd));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(randomDelay() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LOG_DEBUG(@"%@ API request completed", NSStringFromSelector(_cmd));

        PsiCashRequestStatus status = alwaysSucceedPurchase ? kSuccess : [self randomStatusCodeForNewExpiringPurchase];

        if (status == kSuccess) {
            [self expiringPurchaseSuccessWithPrice:expectedPrice andCompletionHandler:completion];
        } else if (status == kExistingTransaction) {
            [self expiringPurchaseExistingTransactionWithPrice:expectedPrice andCompletionHandler:completion];
        } else if (status == kInsufficientBalance) {
            [self expringPurchaseWithInsufficientBalance:expectedPrice andCompletionHandler:completion];
        } else if (status == kTransactionAmountMismatch) {
            [self expringPurchaseWithTransactionAmountMismatch:expectedPrice andCompletionHandler:completion];
        } else if (status == kTransactionTypeNotFound) {
            [self expiringPurchaseWithTransactionTypeNotFound:completion];
        } else if (status == kInvalidTokens) {
            [self expiringPurchaseWithInvalidTokens:completion];
        } else if (status == kServerError) {
            [self expiringPurchaseWithServerError:completion];
        } else {
            assert(FALSE);
        }
    });
}

- (PsiCashRequestStatus)randomStatusCodeForNewExpiringPurchase {
    int r = rand()%7;

    if (r == 0) {
        return kSuccess;
    } else if (r == 1) {
        return kExistingTransaction;
    } else if (r == 2) {
        return kInsufficientBalance;
    } else if (r == 3){
        return kTransactionAmountMismatch;
    } else if (r == 4) {
        return kTransactionTypeNotFound;
    } else if (r == 5) {
        return kInvalidTokens;
    } else {
        return kServerError;
    }

    return kSuccess;
}

- (void)expiringPurchaseSuccessWithPrice:(NSNumber*)price andCompletionHandler:(expiringPurchaseCompletionHandler)completion {
    NSNumber *balance = [NSNumber numberWithUnsignedLongLong:get_client_balance(client)];
    // TODO: auto generate auth token so expiry dates match
    NSString *validAuthTokenForSpeedBoost = @"eyJBdXRob3JpemF0aW9uIjp7IkFjY2Vzc1R5cGUiOiJzcGVlZC1ib29zdCIsIkV4cGlyZXMiOiIyMDE4LTAzLTI3VDIxOjU4OjQ2WiIsIklEIjoiSnNHM3VrR3hVUVhSQU03UG1icEhtUTZuanZiRmplOC95OTRPZ3E1ZnNpaz0ifSwiU2lnbmF0dXJlIjoiMGxOZzdCYXhGWTQrY3hkaVhCeFhRdEhaVTdGQWpFcEZMdUxvS0tuZUZuRi80VVFTZUFpQTVSWUJscnluKzgzZGNDamM5QUduMk9CQjBxaEhzdWRtQ1E9PSIsIlNpZ25pbmdLZXlJRCI6IlJUTnQxNWd6UVBuUmhNbEhmRm5mRjE4eDl3Ri9WNWs0TnhRVU1heFBoMkk9In0K";
   //NSString *invalidAuthTokenForSpeedBoost = @"eyJBdXRob3JpemF0aW9uIjp7IkFjY2Vzc1R5cGUiOiJhcHBsZS1zdWJzY3JpcHRpb24iLCJFeHBpcmVzIjoiMjAxOC0wMy0yN1QyMTo1ODo0NloiLCJJRCI6IkpzRzN1a0d4VVFYUkFNN1BtYnBIbVE2bmp2YkZqZTgveTk0T2dxNWZzaWs9In0sIlNpZ25hdHVyZSI6IjBsTmc3QmF4Rlk0K2N4ZGlYQnhYUXRIWlU3RkFqRXBGTHVMb0tLbmVGbkYvNFVRU2VBaUE1UllCbHJ5bis4M2RjQ2pjOUFHbjJPQkIwcWhIc3VkbUNRPT0iLCJTaWduaW5nS2V5SUQiOiJSVE50MTVnelFQblJoTWxIZkZuZkYxOHg5d0YvVjVrNE54UVVNYXhQaDJJPSJ9";
    if ([balance longValue] >= [price longValue]) {
        make_client_purchase(client, [price unsignedLongLongValue]);
        completion(kSuccess, price, balance, [NSDate dateWithTimeIntervalSinceNow:10], validAuthTokenForSpeedBoost, nil);
    } else {
        completion(kInsufficientBalance, price, balance, nil, nil, nil);
    }
}

- (void)expiringPurchaseExistingTransactionWithPrice:(NSNumber*)price andCompletionHandler:(expiringPurchaseCompletionHandler)completion {
    // TODO: auto-generate auth token so expiry dates match
    NSString *validAuthTokenForSpeedBoost = @"eyJBdXRob3JpemF0aW9uIjp7IkFjY2Vzc1R5cGUiOiJzcGVlZC1ib29zdCIsIkV4cGlyZXMiOiIyMDE4LTAzLTI3VDIxOjU4OjQ2WiIsIklEIjoiSnNHM3VrR3hVUVhSQU03UG1icEhtUTZuanZiRmplOC95OTRPZ3E1ZnNpaz0ifSwiU2lnbmF0dXJlIjoiMGxOZzdCYXhGWTQrY3hkaVhCeFhRdEhaVTdGQWpFcEZMdUxvS0tuZUZuRi80VVFTZUFpQTVSWUJscnluKzgzZGNDamM5QUduMk9CQjBxaEhzdWRtQ1E9PSIsIlNpZ25pbmdLZXlJRCI6IlJUTnQxNWd6UVBuUmhNbEhmRm5mRjE4eDl3Ri9WNWs0TnhRVU1heFBoMkk9In0K";

    cash_client_balance_t b = get_client_balance(client);
    NSNumber *balance = [NSNumber numberWithUnsignedLongLong:b];
    completion(kExistingTransaction, price, balance, [NSDate dateWithTimeIntervalSinceNow:10], validAuthTokenForSpeedBoost, nil);
}

- (void)expringPurchaseWithInsufficientBalance:(NSNumber*)expectedPrice andCompletionHandler:(expiringPurchaseCompletionHandler)completion {
    // just zero out balance and fail transaction
    cash_client_balance_t b = get_client_balance(client);
    make_client_purchase(client, b);
    b = get_client_balance(client);
    NSNumber *balance = [NSNumber numberWithUnsignedLongLong:b];
    completion(kInsufficientBalance, expectedPrice, balance, nil, nil, nil);
}

- (void)expringPurchaseWithTransactionAmountMismatch:(NSNumber*)expectedPrice andCompletionHandler:(expiringPurchaseCompletionHandler)completion {
    cash_client_balance_t b = get_client_balance(client);
    NSNumber *balance = [NSNumber numberWithUnsignedLongLong:b];
    completion(kTransactionAmountMismatch, [NSNumber numberWithLong:[expectedPrice longValue] * 2], balance, nil, nil, nil);
}

- (void)expiringPurchaseWithTransactionTypeNotFound:(expiringPurchaseCompletionHandler)completion {
    completion(kTransactionTypeNotFound, nil, nil, nil, nil, nil);
}

- (void)expiringPurchaseWithInvalidTokens:(expiringPurchaseCompletionHandler)completion {
    completion(kInvalidTokens, nil, nil, nil, nil, nil);
}

- (void)expiringPurchaseWithServerError:(expiringPurchaseCompletionHandler)completion {
    completion(kServerError, nil, nil, nil, nil, nil);
}

#pragma mark - demo mode

- (void)startDemoMode {
    start_demo_mode(client);
}

@end
