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

//
//  PsiCashAPIModels.h
//  PsiCashLib
//

#ifndef PsiCashAPIModels_h
#define PsiCashAPIModels_h

#import <Foundation/Foundation.h>
#import <PsiCashLib/PsiCash.h>
#import <PsiCashLib/PurchasePrice.h>


#pragma mark - RefreshResultModel

@interface PsiCashRefreshResultModel : NSObject

@property (nonatomic, readwrite, assign) BOOL inProgress;

@property (nonatomic, readwrite) PsiCashStatus status;

@property (nonatomic, readwrite) NSError *error;

+ (PsiCashRefreshResultModel*)inProgress;
+ (PsiCashRefreshResultModel*)success;

@end

#pragma mark - MakePurchaseResultModel

@interface PsiCashMakePurchaseResultModel : NSObject

@property (nonatomic, readwrite, assign) BOOL inProgress;

@property (nonatomic, readwrite) PsiCashStatus status;

@property (nonatomic, readwrite) PsiCashPurchase *purchase;

@property (nonatomic, readwrite) NSError *error;

+ (PsiCashMakePurchaseResultModel*)inProgress;
+ (PsiCashMakePurchaseResultModel*)failedWithStatus:(PsiCashStatus)status
                                           andError:(NSError*)error;
+ (PsiCashMakePurchaseResultModel*)successWithStatus:(PsiCashStatus)status
                                         andPurchase:(PsiCashPurchase*)purchase
                                            andError:(NSError*)error;

@end


#endif /* PsiCashAPIModels_h */
