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

#import <UIKit/UIKit.h>
#import "PsiCashClientModel.h"
#import "NSDate+Comparator.h"

@implementation PsiCashClientModel

+ (PsiCashClientModel*)clientModelWithAuthPackage:(PsiCashAuthPackage*)authPackage
                         andBalanceInNanoPsi:(UInt64)balance
                        andSpeedBoostProduct:(PsiCashSpeedBoostProduct*)speedBoostProduct
                         andPendingPurchases:(NSArray<id<PsiCashProductSKU>>*)pendingPurchases
                 andActiveSpeedBoostPurchase:(PsiCashPurchase* /* TODO: typing */)activeSpeedBoostPurchase {
    PsiCashClientModel *clientModel = [[PsiCashClientModel alloc] init];
    clientModel.authPackage = authPackage;
    clientModel.balanceInNanoPsi = balance;
    clientModel.balanceInPsi = balance / 1e9;
    clientModel.speedBoostProduct = speedBoostProduct;
    clientModel.pendingPurchases = pendingPurchases;
    clientModel.activeSpeedBoostPurchase = activeSpeedBoostPurchase;
    return clientModel;
}

- (NSNumber*)hoursEarned {
    NSNumber *maxHoursEarned = 0;

    for (PsiCashSpeedBoostProductSKU *sku in [self.speedBoostProduct skusOrderedByPriceAscending]) {
        if (self.balanceInNanoPsi >= [sku.price unsignedLongLongValue]) {
            if (sku.hours > maxHoursEarned) {
                maxHoursEarned = sku.hours;
            }
        }
    }

    return maxHoursEarned;
}

- (PsiCashSpeedBoostProductSKU*)minSpeedBoostPurchase {
    NSArray<PsiCashSpeedBoostProductSKU*> *skus = [self.speedBoostProduct skusOrderedByPriceAscending];
    if ([skus count] == 0) {
        nil;
    }
    return [skus objectAtIndex:0];
}

- (BOOL)hasActiveSpeedBoostPurchase {
    if (self.activeSpeedBoostPurchase != nil && [[NSDate date] before:[self.activeSpeedBoostPurchase expiry]]) {
        return TRUE;
    }
    return FALSE;
}

- (int)minutesOfSpeedBoostRemaining {
    NSTimeInterval timeRemaing = [[self.activeSpeedBoostPurchase expiry] timeIntervalSinceNow];
    return timeRemaing < 0 ? 0 : (int)(timeRemaing / 60);
}

- (BOOL)hasPendingPurchase {
    return [self.pendingPurchases count] > 0;
}

- (BOOL)hasAuthPackage {
    return self.authPackage != nil;
}

#pragma mark - NSCopying protocol

- (id)copyWithZone:(NSZone *)zone {
    return [PsiCashClientModel clientModelWithAuthPackage:self.authPackage
                                 andBalanceInNanoPsi:self.balanceInNanoPsi
                                andSpeedBoostProduct:self.speedBoostProduct /* TODO: copy this? */
                                 andPendingPurchases:self.pendingPurchases /* TODO: copy this? */
                         andActiveSpeedBoostPurchase:self.activeSpeedBoostPurchase];
}

@end

