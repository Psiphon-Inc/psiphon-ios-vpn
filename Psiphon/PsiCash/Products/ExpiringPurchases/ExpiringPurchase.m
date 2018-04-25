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

#import "ExpiringPurchase.h"
#import "PsiCashSpeedBoostProduct.h"
#import "PsiFeedbackLogger.h"

@interface ExpiringPurchase ()
@property (nonatomic, readwrite) AuthorizationToken *authToken;
@property (nonatomic, readwrite) NSString *productName;
@property (nonatomic, readwrite) NSDate *expiryDate;
@property (nonatomic, readwrite) id<PsiCashProductSKU> sku;
@end

@implementation ExpiringPurchase

+ (ExpiringPurchase*)expiringPurchaseWithProductName:(NSString*)productName SKU:(id<PsiCashProductSKU>)sku expiryDate:(NSDate*)date andAuthToken:(AuthorizationToken*)authToken {
    ExpiringPurchase *instance = [[ExpiringPurchase alloc] init];
    instance.authToken = authToken;
    instance.productName = productName;
    instance.sku = sku;
    instance.expiryDate = date;
    return instance;
}

#pragma mark - Persistable protocol

+ (ExpiringPurchase*)fromDictionary:(nonnull NSDictionary *)dictionary {
    NSString *authTokenBase64Representation = [dictionary objectForKey:@"auth_token"];
    AuthorizationToken *authToken = [[AuthorizationToken alloc] initWithEncodedToken:authTokenBase64Representation];

    if (authToken == nil) {
        return nil;
    }

    NSString *productName = [dictionary objectForKey:@"product_name"];
    if (productName == nil) {
        return nil;
    }

    if (![authToken.accessType isEqualToString:productName]) {
        return nil;
    }

    NSDictionary *skuDict = [dictionary objectForKey:@"sku"];
    if (skuDict == nil) {
        return nil;
    }

    PsiCashSpeedBoostProductSKU *sku = [PsiCashSpeedBoostProductSKU fromDictionary:skuDict];
    if (sku == nil) {
        return nil;
    }

    NSDate *expiryDate = [dictionary objectForKey:@"expiry_date"];
    if (expiryDate == nil) {
        return nil;
    }

    return [ExpiringPurchase expiringPurchaseWithProductName:productName SKU:sku expiryDate:expiryDate andAuthToken:authToken];
}

- (NSDictionary*)dictionaryRepresentation {
    return @{
             @"auth_token": self.authToken.base64Representation,
             @"expiry_date": self.expiryDate,
             @"product_name": self.productName,
             @"sku": [self.sku dictionaryRepresentation]
             };
}

@end
