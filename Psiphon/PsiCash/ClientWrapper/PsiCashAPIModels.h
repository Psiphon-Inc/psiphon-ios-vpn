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

#import <Foundation/Foundation.h>
#import "PsiCash.h"

#pragma mark - RefreshResultModel

@interface PsiCashRefreshResultModel : NSObject

@property (nonatomic, readwrite, assign) BOOL inProgress;

@property (nonatomic, readwrite) PsiCashRequestStatus status;

@property (nonatomic, readwrite) NSArray *validTokenTypes;

@property (nonatomic, readwrite) BOOL isAccount;

@property (nonatomic, readwrite) NSNumber *balance;

@property (nonatomic, readwrite) NSArray<PsiCashPurchasePrice*> *purchasePrices;

/** Error with domain PsiCashAuthenticationResultErrorDomain */
@property (nonatomic, readwrite) NSError *error;

+ (PsiCashRefreshResultModel*)inProgress;
+ (PsiCashRefreshResultModel*)successWithValidTokenTypes:(NSArray*)validTokenTypes balance:(NSNumber*)balance andPurchasePrices:(NSArray<PsiCashPurchasePrice*>*)purchasePrices;

@end

#pragma mark - MakePurchaseResultModel

@interface PsiCashMakePurchaseResultModel : NSObject

@property (nonatomic, readwrite, assign) BOOL inProgress;

@property (nonatomic, readwrite) PsiCashRequestStatus status;

@property (nonatomic, readwrite) NSNumber *price;

@property (nonatomic, readwrite) NSNumber *balance;

@property (nonatomic, readwrite) NSDate *expiry;

@property (nonatomic, readwrite) NSString *authorization;

/** Error with domain PsiCashAuthenticationResultErrorDomain */
@property (nonatomic, readwrite) NSError *error;

+ (PsiCashMakePurchaseResultModel*)inProgress;
+ (PsiCashMakePurchaseResultModel*)failedWithStatus:(PsiCashRequestStatus)status
                                      andPrice:(NSNumber*)price
                                    andBalance:(NSNumber*)balance
                                     andExpiry:(NSDate*)expiry
                              andAuthorization:(NSString*)authorization
                                      andError:(NSError*)error;
+ (PsiCashMakePurchaseResultModel*)successWithStatus:(PsiCashRequestStatus)status
                                       andPrice:(NSNumber*)price
                                     andBalance:(NSNumber*)balance
                                      andExpiry:(NSDate*)expiry
                               andAuthorization:(NSString*)authorization
                                       andError:(NSError*)error;

@end
