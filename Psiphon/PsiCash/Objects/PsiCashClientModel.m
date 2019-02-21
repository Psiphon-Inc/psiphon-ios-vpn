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
                                       andBalance:(NSNumber*_Nonnull)balance
                             andSpeedBoostProduct:(PsiCashSpeedBoostProduct*)speedBoostProduct
                              andPendingPurchases:(NSArray<id<PsiCashProductSKU>>*)pendingPurchases
                      andActiveSpeedBoostPurchase:(PsiCashPurchase* /* TODO: typing */)activeSpeedBoostPurchase
                                andRefreshPending:(BOOL)refreshPending {
    PsiCashClientModel *clientModel = [[PsiCashClientModel alloc] init];
    clientModel.authPackage = authPackage;
    clientModel.balance = balance;
    clientModel.speedBoostProduct = speedBoostProduct;
    clientModel.pendingPurchases = pendingPurchases;
    clientModel.activeSpeedBoostPurchase = activeSpeedBoostPurchase;
    clientModel.refreshPending = refreshPending;
    return clientModel;
}

+ (NSString*)formattedBalance:(NSNumber*)balance {
    if (!balance) {
        balance = [NSNumber numberWithInteger:0];
    }
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    return [formatter stringFromNumber:[NSNumber numberWithDouble:balance.doubleValue/1e9]];
}

- (PsiCashSpeedBoostProductSKU*)maxSpeedBoostPurchaseEarned {
    PsiCashSpeedBoostProductSKU *maxHoursEarned;

    for (PsiCashSpeedBoostProductSKU *sku in [self.speedBoostProduct skusOrderedByPriceAscending]) {
        if (self.balance.doubleValue >= sku.price.doubleValue) {
            if (maxHoursEarned == nil || sku.hours > maxHoursEarned.hours) {
                maxHoursEarned = sku;
            }
        }
    }

    return maxHoursEarned;
}

- (PsiCashSpeedBoostProductSKU*)minSpeedBoostPurchaseAvailable {
    NSArray<PsiCashSpeedBoostProductSKU*> *skus = [self.speedBoostProduct skusOrderedByPriceAscending];
    if ([skus count] == 0) {
        nil;
    }
    return [skus objectAtIndex:0];
}

- (BOOL)hasActiveSpeedBoostPurchase {
    if (self.activeSpeedBoostPurchase != nil && [[NSDate date] before:self.activeSpeedBoostPurchase.localTimeExpiry]) {
        return TRUE;
    }
    return FALSE;
}

- (int)minutesOfSpeedBoostRemaining {
    NSTimeInterval timeRemaing = [self.activeSpeedBoostPurchase.localTimeExpiry timeIntervalSinceNow];
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
    PsiCashClientModel *copy = [PsiCashClientModel
                                clientModelWithAuthPackage:self.authPackage
                                                andBalance:self.balance
                                      andSpeedBoostProduct:self.speedBoostProduct /* TODO: copy this? */
                                       andPendingPurchases:self.pendingPurchases /* TODO: copy this? */
                               andActiveSpeedBoostPurchase:self.activeSpeedBoostPurchase
                                         andRefreshPending:self.refreshPending];
    copy.onboarded = self.onboarded;
    return copy;
}

@end

