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

#import "PsiCashSpeedBoostProduct.h"
#import <PsiCashLib/PsiCash.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - PsiCashSpeedBoostProductSKU

@interface PsiCashSpeedBoostProductSKU ()
@property (nonatomic, readwrite) NSString *distinguisher;
@property (nonatomic, readwrite) NSNumber *price;
@property (nonatomic, readwrite) NSNumber *variant;
@end

#pragma mark -

@implementation PsiCashSpeedBoostProductSKU

+ (PsiCashSpeedBoostProductSKU*)skuWitDistinguisher:(NSString*)distinguisher withHours:(NSNumber*)hours andPrice:(NSNumber*)price {
    PsiCashSpeedBoostProductSKU *sku = [[PsiCashSpeedBoostProductSKU alloc] init];
    sku.distinguisher = distinguisher;
    sku.price = price;
    sku.variant = hours;
    return sku;
}

- (NSNumber*)hours {
    return self.variant;
}

- (double)priceInPsi {
    return [self.price doubleValue] / 1e9;
}

- (NSDictionary*)jsonDict {
    return @{
             @"distinguisher": self.distinguisher,
             @"price": self.price,
             @"variant": self.variant
             };
}

- (NSString*)json {
    NSDictionary *dict = [self jsonDict];

    if (![NSJSONSerialization isValidJSONObject:dict]) {
        return @"{\"error\": \"invalid JSON object\"}";
    }

    NSError *writeError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&writeError];
    if (writeError) {
        return [NSString stringWithFormat:@"{\"error\": \"%@\"}", writeError.localizedDescription];
    }
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    return jsonString;
}

@end

#pragma mark - PsiCashSpeedBoostProduct

@interface PsiCashSpeedBoostProduct ()
@property (nonatomic, readwrite) NSArray<PsiCashSpeedBoostProductSKU*> *skusOrderedByPriceAscending;
@end

#pragma mark -

@implementation PsiCashSpeedBoostProduct

#pragma mark - PsiCashProduct protocol

+ (NSString * _Nonnull)purchaseClass {
    return @"speed-boost";
}

+ (PsiCashSpeedBoostProduct*)productWithSKUs:(NSArray<PsiCashSpeedBoostProductSKU*>*)skus {
    PsiCashSpeedBoostProduct *product = [[PsiCashSpeedBoostProduct alloc] init];
    NSArray<PsiCashSpeedBoostProductSKU*>* orderedSkus = [skus sortedArrayUsingComparator:^NSComparisonResult(PsiCashSpeedBoostProductSKU *p1, PsiCashSpeedBoostProductSKU *p2) {
        if (p1.price < p2.price) {
            return NSOrderedAscending;
        } else if (p1.price > p2.price) {
            return NSOrderedDescending;
        } else if (p1.hours < p2.hours) {
            return NSOrderedAscending;
        } else if (p1.hours > p2.hours) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    product.skusOrderedByPriceAscending = orderedSkus;
    return product;
}

- (PsiCashSpeedBoostProductSKU*)productSKUWithDistinguisher:(NSString*_Nonnull)distinguisher {
    for (PsiCashSpeedBoostProductSKU *sku in self.skusOrderedByPriceAscending) {
        if ([sku.distinguisher isEqualToString:distinguisher]) {
            return sku;
        }
    }
    return nil;
}

@end

NS_ASSUME_NONNULL_END

