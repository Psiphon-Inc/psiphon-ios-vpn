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

#import "PsiCashClientModelEmitter.h"
#import "ReactiveObjC.h"

@interface PsiCashClientModelEmitter ()
@property (nonatomic, readwrite) RACReplaySubject *emitter;
@end

@implementation PsiCashClientModelEmitter {
    PsiCashClientModel *model;
}

- (id)init {
    self = [super init];
    if (self) {
        self.emitter = [RACReplaySubject replaySubjectWithCapacity:1];
        model = [PsiCashClientModel clientModelWithAuthPackage:nil
                                      andBalanceInNanoPsi:0
                                     andSpeedBoostProduct:nil
                                      andPendingPurchases:nil
                              andActiveSpeedBoostPurchase:nil];
    }
    return self;
}

- (void)emitNextClientModel {
    dispatch_async(dispatch_get_main_queue(), ^{
        PsiCashClientModel *copiedModel = [model copy];
        [self.emitter sendNext:copiedModel];
    });
}

- (void)updateAuthPackage:(PsiCashAuthPackage*)authPackage {
    model.authPackage = authPackage;
}

- (void)updateBalanceInNanoPsi:(UInt64)balanceInNanoPsi {
    model.balanceInNanoPsi = balanceInNanoPsi;
}

- (void)updateSpeedBoostProduct:(PsiCashSpeedBoostProduct*)speedBoostProduct {
    model.speedBoostProduct = speedBoostProduct;
}

- (void)updateSpeedBoostProductSKU:(PsiCashSpeedBoostProductSKU*)old withNewPrice:(NSNumber*)price {
    NSMutableArray<PsiCashSpeedBoostProductSKU*>* newSKUs = [NSMutableArray arrayWithArray:model.speedBoostProduct.skusOrderedByPriceAscending];
    [newSKUs removeObject:old];
    PsiCashSpeedBoostProductSKU *newSKU = [PsiCashSpeedBoostProductSKU skuWitDistinguisher:old.distinguisher withHours:old.hours andPrice:price];
    [newSKUs addObject:newSKU];
    model.speedBoostProduct = [PsiCashSpeedBoostProduct productWithSKUs:newSKUs];
}

- (void)removeSpeedBoostProductSKU:(PsiCashSpeedBoostProductSKU*)sku {
    // Silently fail if sku doesn't exist
    NSMutableArray<PsiCashSpeedBoostProductSKU*>* newSKUs = [NSMutableArray arrayWithArray:model.speedBoostProduct.skusOrderedByPriceAscending];
    [newSKUs removeObject:sku];
    model.speedBoostProduct = [PsiCashSpeedBoostProduct productWithSKUs:newSKUs];
}

- (void)updatePendingPurchases:(NSArray<id<PsiCashProductSKU>>*)purchases {
    model.pendingPurchases = purchases;
}

- (void)updateActivePurchases:(NSArray<ExpiringPurchase*>*)activePurchases {
    for (ExpiringPurchase *p in activePurchases) {
        if ([p.productName isEqualToString:[PsiCashSpeedBoostProduct purchaseClass]]) {
            model.activeSpeedBoostPurchase = p;
            return;
        }
    }
    model.activeSpeedBoostPurchase = nil;
}

@end
