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

#import "PsiCashSpeedBoostProduct+PsiCashPurchasePrice.h"
#import "PsiCashTypes.h"
#import "PsiFeedbackLogger.h"

NS_ASSUME_NONNULL_BEGIN

@implementation PsiCashSpeedBoostProduct (PsiCashPurchasePrice)

+ (PsiCashSpeedBoostProduct*_Nullable)productWithPurchasePrices:(NSArray<PsiCashPurchasePrice*>*)purchasePrices {
    NSMutableArray<PsiCashSpeedBoostProductSKU*>* skus = [[NSMutableArray alloc] init];

    NSRegularExpression *regex = [PsiCashSpeedBoostProduct regexForHoursDistinguisher];
    if (regex == nil) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s failed to get regex for distinguisher (this should never happen).", __FUNCTION__];
        return nil;
    }

    for (PsiCashPurchasePrice *purchasePrice in purchasePrices) {
        if (![[PsiCashSpeedBoostProduct purchaseClass] isEqualToString:purchasePrice.transactionClass]) {
            [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s encountered invalid transaction class %@ in purchase prices %@.", __FUNCTION__, purchasePrice.transactionClass, purchasePrices];
            return nil;
        }
        NSNumber *hours = [PsiCashSpeedBoostProduct hoursFromDistinguisher:purchasePrice.distinguisher withRegex:regex droppingNTrailingChars:2];
        if (hours == nil) {
            // TODO: (1.0) make this DEBUG only
            // TODO: (1.0) log error
            //[PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s failed to parse distinguisher %@ in SpeedBoostProductSKU into hours.", __FUNCTION__, purchasePrice.distinguisher];
            // Try mins
            NSNumber *mins = [PsiCashSpeedBoostProduct hoursFromDistinguisher:purchasePrice.distinguisher withRegex:[PsiCashSpeedBoostProduct regexForMinsDistinguisher] droppingNTrailingChars:3];
            if (mins == nil) {
                assert(FALSE);
            }
            hours = [NSNumber numberWithDouble:[mins doubleValue]/60];
        } else if ([hours integerValue] < 1) {
            // This will be caught before here by the regex
            [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s encountered invalid number of hours %@ in SpeedBoostProductSKU.", __FUNCTION__, hours];
            return nil;
        }

        PsiCashSpeedBoostProductSKU *sku = [PsiCashSpeedBoostProductSKU skuWitDistinguisher:purchasePrice.distinguisher withHours:hours andPrice:purchasePrice.price];
        [skus addObject:sku];
    }

    return [PsiCashSpeedBoostProduct productWithSKUs:skus];
}

// TODO: (1.0) make this DEBUG only
+ (NSRegularExpression*_Nullable)regexForMinsDistinguisher {
    // "1hr", "2hr", "3hr", ...
    NSString *pattern = @"[0-9]+min";
    NSError  *error = nil;

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error]; // TODO: compile the regex once
    if (error != nil) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s failed to compile regex pattern %@ (this should never happen).", __FUNCTION__, pattern];
        return nil;
    }
    return regex;
}

+ (NSRegularExpression*_Nullable)regexForHoursDistinguisher {
    // "1hr", "2hr", "3hr", ...
    NSString *pattern = @"[0-9]+hr";
    NSError  *error = nil;

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error]; // TODO: compile the regex once
    if (error != nil) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s failed to compile regex pattern %@ (this should never happen).", __FUNCTION__, pattern];
        return nil;
    }
    return regex;
}

+ (NSNumber*_Nullable)hoursFromDistinguisher:(NSString*)distinguisher withRegex:(NSRegularExpression*)regex droppingNTrailingChars:(int)dropN {
    NSRange searchRange = NSMakeRange(0, [distinguisher length]);

    NSArray<NSTextCheckingResult*> *matches = [regex matchesInString:distinguisher options:0 range:searchRange];
    if (matches == nil || matches.count == 0) {
        //[PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s received invalid distinguisher %@ for SpeedBoostProductSKU; no matches for regex found.", __FUNCTION__, distinguisher];
        return nil;
    } else if (matches.count > 1) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s received invalid distinguisher %@ for SpeedBoostProductSKU; multiple matches for regex found.", __FUNCTION__, distinguisher];
        return nil;
    }

    NSTextCheckingResult *match = [matches objectAtIndex:0];
    if (match.range.length != distinguisher.length) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s received invalid distinguisher %@ for SpeedBoostProductSKU; expected to match whole string with regex %@.", __FUNCTION__, distinguisher, regex.pattern];
        return nil;
    }

    NSString *matchText = [distinguisher substringWithRange:NSMakeRange(match.range.location, match.range.length - dropN)];

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterNoStyle;
    NSNumber *hours = [formatter numberFromString:matchText];
    if (hours == nil) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s failed to convert NSString %@ into NSNumber.", __FUNCTION__, matchText];
    }

    return hours;
}

@end

NS_ASSUME_NONNULL_END
