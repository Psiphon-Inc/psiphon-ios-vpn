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
#import "PsiCashSpeedBoostProduct.h"
#import "PsiCashClientModel.h"
#import "PsiCashAuthPackage.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * PsiCashClientModelStagingArea provides a staging area to accumulate changes
 * to a copy of an instance of PsiCashClientModel.
 */
@interface PsiCashClientModelStagingArea : NSObject

/**
 * The PsiCashClientModel that all the mutations have been applied to.
 */
@property (nonatomic, readonly) PsiCashClientModel *stagedModel;

/**
 * Initializes PsiCashClientModelStagingArea with a copy of PsiCashClientModel.
 * @param model The model to copy from.
 */
- (instancetype)initWithModel:(PsiCashClientModel *_Nullable)model;

- (void)updateAuthPackage:(PsiCashAuthPackage*_Nullable)authPackage;

/**
 * Update balance of model in staging area.
 * @note If balance is nil the inner client model's balance will be updated to an NSNumber of 0.
 */
- (void)updateBalance:(NSNumber*_Nullable)balance;

- (void)updateSpeedBoostProduct:(PsiCashSpeedBoostProduct*)speedBoostProduct;

- (void)updateSpeedBoostProductSKU:(PsiCashSpeedBoostProductSKU*)old withNewPrice:(NSNumber*)price;

- (void)removeSpeedBoostProductSKU:(PsiCashSpeedBoostProductSKU*)sku;

- (void)updatePendingPurchases:(NSArray<id<PsiCashProductSKU>>*_Nullable)purchases;

- (void)updateActivePurchases:(NSArray<PsiCashPurchase*>*)activePurchases;

- (void)updateRefreshPending:(BOOL)refreshPending;

@end

NS_ASSUME_NONNULL_END
