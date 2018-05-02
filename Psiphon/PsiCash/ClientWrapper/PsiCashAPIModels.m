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

#import "PsiCashAPIModels.h"

@implementation PsiCashRefreshResultModel

+ (PsiCashRefreshResultModel*)inProgress {
    PsiCashRefreshResultModel *instance = [[PsiCashRefreshResultModel alloc] init];
    instance.inProgress = YES;
    instance.status = PsiCashStatus_Invalid;
    instance.validTokenTypes = nil;
    instance.isAccount = nil;
    instance.balance = nil;
    instance.purchasePrices = nil;
    instance.error = nil;
    return instance;
}

+ (PsiCashRefreshResultModel*)successWithValidTokenTypes:(NSArray*)validTokenTypes balance:(NSNumber*)balance andPurchasePrices:(NSArray<PsiCashPurchasePrice*>*)purchasePrices {
    PsiCashRefreshResultModel *instance = [[PsiCashRefreshResultModel alloc] init];
    instance.inProgress = NO;
    instance.status = PsiCashStatus_Success;
    instance.validTokenTypes = validTokenTypes;
    instance.isAccount = NO;
    instance.balance = balance;
    instance.purchasePrices = purchasePrices;
    instance.error = nil;
    return instance;
}

@end

@implementation PsiCashMakePurchaseResultModel

+ (PsiCashMakePurchaseResultModel*)inProgress {
    PsiCashMakePurchaseResultModel *instance = [[PsiCashMakePurchaseResultModel alloc] init];
    instance.inProgress = YES;
    instance.status = PsiCashStatus_Invalid;
    instance.price = nil;
    instance.balance = nil;
    instance.expiry = nil;
    instance.authorization = nil;
    instance.error = nil;
    return instance;
}

+ (PsiCashMakePurchaseResultModel*)failedWithStatus:(PsiCashStatus)status
                                      andPrice:(NSNumber*)price
                                    andBalance:(NSNumber*)balance
                                     andExpiry:(NSDate*)expiry
                              andAuthorization:(NSString*)authorization
                                      andError:(NSError*)error {
    PsiCashMakePurchaseResultModel *instance = [[PsiCashMakePurchaseResultModel alloc] init];
    instance.inProgress = NO;
    instance.status = status;
    instance.price = price;
    instance.balance = balance;
    instance.expiry = expiry;
    instance.authorization = authorization;
    instance.error = error;
    return instance;
}

+ (PsiCashMakePurchaseResultModel*)successWithStatus:(PsiCashStatus)status
                                       andPrice:(NSNumber*)price
                                     andBalance:(NSNumber*)balance
                                      andExpiry:(NSDate*)expiry
                               andAuthorization:(NSString*)authorization
                                       andError:(NSError*)error {
    PsiCashMakePurchaseResultModel *instance = [[PsiCashMakePurchaseResultModel alloc] init];
    instance.inProgress = NO;
    instance.status = status;
    instance.price = price;
    instance.balance = balance;
    instance.expiry = expiry;
    instance.authorization = authorization;
    instance.error = error;
    return instance;
}

@end
