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
#import <PsiCashLib/Purchase.h>
#import "PsiCashSpeedBoostProduct.h"
#import "PsiCashAuthPackage.h"

@interface PsiCashClientModel : NSObject
@property (strong, atomic) PsiCashAuthPackage *authPackage;
@property (strong, atomic) NSNumber *balance;
@property (strong, atomic) PsiCashSpeedBoostProduct *speedBoostProduct;
@property (strong, atomic) NSArray<id<PsiCashProductSKU>> *pendingPurchases;
@property (strong, atomic) PsiCashPurchase *activeSpeedBoostPurchase;
@property (nonatomic, assign) BOOL refreshPending;
+ (PsiCashClientModel*)clientModelWithAuthPackage:(PsiCashAuthPackage*)authPackage
                                       andBalance:(NSNumber*)balance
                             andSpeedBoostProduct:(PsiCashSpeedBoostProduct*)speedBoostProduct
                              andPendingPurchases:(NSArray<id<PsiCashProductSKU>>*)pendingPurchases
                      andActiveSpeedBoostPurchase:(PsiCashPurchase*)activeSpeedBoostPurchase
                                andRefreshPending:(BOOL)refreshPending;
+ (NSString*)formattedBalance:(NSNumber*)balance;
- (PsiCashSpeedBoostProductSKU*)maxSpeedBoostPurchaseEarned;
- (PsiCashSpeedBoostProductSKU*)minSpeedBoostPurchaseAvailable;
- (BOOL)hasActiveSpeedBoostPurchase;
- (int)minutesOfSpeedBoostRemaining;
- (BOOL)hasPendingPurchase;
- (BOOL)hasAuthPackage;
@end

@protocol PsiCashClientModelReceiver
-(void)bindWithModel:(PsiCashClientModel*)clientModel;
@property (atomic, readonly) PsiCashClientModel *model;
@end
