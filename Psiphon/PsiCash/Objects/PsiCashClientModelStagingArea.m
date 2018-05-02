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

#import "PsiCashClientModelStagingArea.h"
#import "NSDate+Comparator.h"

@interface PsiCashClientModelStagingArea ()

@property (nonatomic, readwrite) PsiCashClientModel *stagedModel;

@end

@implementation PsiCashClientModelStagingArea

- (instancetype)initWithModel:(PsiCashClientModel *)model {
    self = [super init];
    if (self) {
        if (model) {
            _stagedModel = [model copy];
        } else {
            _stagedModel = [PsiCashClientModel clientModelWithAuthPackage:nil
                                                      andBalanceInNanoPsi:0
                                                     andSpeedBoostProduct:nil
                                                      andPendingPurchases:nil
                                              andActiveSpeedBoostPurchase:nil];
        }
    }
    return self;
}

- (void)updateAuthPackage:(PsiCashAuthPackage*)authPackage {
    self.stagedModel.authPackage = authPackage;
}

- (void)updateBalanceInNanoPsi:(UInt64)balanceInNanoPsi {
    self.stagedModel.balanceInNanoPsi = balanceInNanoPsi;
}

- (void)updateSpeedBoostProduct:(PsiCashSpeedBoostProduct*)speedBoostProduct {
    self.stagedModel.speedBoostProduct = speedBoostProduct;
}

- (void)updateSpeedBoostProductSKU:(PsiCashSpeedBoostProductSKU*)old withNewPrice:(NSNumber*)price {
    NSMutableArray<PsiCashSpeedBoostProductSKU*>* newSKUs = [NSMutableArray arrayWithArray:self.stagedModel.speedBoostProduct.skusOrderedByPriceAscending];
    [newSKUs removeObject:old];
    PsiCashSpeedBoostProductSKU *newSKU = [PsiCashSpeedBoostProductSKU skuWitDistinguisher:old.distinguisher withHours:old.hours andPrice:price];
    [newSKUs addObject:newSKU];
    self.stagedModel.speedBoostProduct = [PsiCashSpeedBoostProduct productWithSKUs:newSKUs];
}

- (void)removeSpeedBoostProductSKU:(PsiCashSpeedBoostProductSKU*)sku {
    // Silently fail if sku doesn't exist
    NSMutableArray<PsiCashSpeedBoostProductSKU*>* newSKUs = [NSMutableArray arrayWithArray:self.stagedModel.speedBoostProduct.skusOrderedByPriceAscending];
    [newSKUs removeObject:sku];
    self.stagedModel.speedBoostProduct = [PsiCashSpeedBoostProduct productWithSKUs:newSKUs];
}

- (void)updatePendingPurchases:(NSArray<id<PsiCashProductSKU>>*)purchases {
    self.stagedModel.pendingPurchases = purchases;
}

- (void)updateActivePurchases:(NSArray<PsiCashPurchase*>*)activePurchases {
    for (PsiCashPurchase *p in activePurchases) {
        if ([p.transactionClass isEqualToString:[PsiCashSpeedBoostProduct purchaseClass]] && [p.expiry after:[NSDate date]]) {
            self.stagedModel.activeSpeedBoostPurchase = p;
            return;
        }
    }
    self.stagedModel.activeSpeedBoostPurchase = nil;
}

@end
