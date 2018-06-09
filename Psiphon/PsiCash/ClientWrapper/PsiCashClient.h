/*
 * Copyright (c) 2017, Psiphon Inc.
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
#import "PsiCashClientModelStagingArea.h"
#import "PsiCashSpeedBoostProduct.h"
#import "ReactiveObjC.h"

@interface PsiCashClient : NSObject

@property (nonatomic, readonly) RACReplaySubject<PsiCashClientModel *> *clientModelSignal;

+ (instancetype)sharedInstance;

- (NSURL*)modifiedHomePageURL:(NSURL*)url;

- (void)scheduleStateRefresh;

- (void)purchaseSpeedBoostProduct:(PsiCashSpeedBoostProductSKU*)sku;
/**
 * @brief Removes any purchases that the extension has marked as invalid from the client model.
 */
- (void)authorizationsMarkedExpired;

- (NSString*)logForFeedback;

@end
