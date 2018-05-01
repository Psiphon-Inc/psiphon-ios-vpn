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

#import "PsiCashPurchaseAlertView.h"
#import "PsiCashClient.h"

@interface PsiCashPurchaseAlertView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@property (atomic, readwrite) PsiCashPurchaseView *purchaseView;
@property (atomic, readwrite) PsiCashSpeedBoostProductSKU *lastSKUEmitted;
@end

#pragma mark -

@implementation PsiCashPurchaseAlertView {
    BOOL alreadySpeedBoosting;
}

+ (PsiCashPurchaseAlertView*)purchaseAlert {
    PsiCashPurchaseAlertView *alertView = [[PsiCashPurchaseAlertView alloc] init];
    alertView->alreadySpeedBoosting = NO;

    PsiCashPurchaseView *purchaseView = [[PsiCashPurchaseView alloc] initWithFrame:CGRectMake(0, 0, 250, 150)];
    purchaseView.delegate = alertView;
    alertView.purchaseView = purchaseView;
    alertView.containerView = purchaseView;

    alertView.buttonTitles = [NSMutableArray arrayWithObjects:@"Buy", @"Cancel", nil];
    alertView.closeOnTouchUpOutside = YES;
    alertView.onButtonTouchUpInside = ^(CustomIOSAlertView *alertView, int buttonIndex) {
        PsiCashPurchaseAlertView *purchaseAlertView = (PsiCashPurchaseAlertView*)alertView;
        [purchaseAlertView.controllerDelegate stateBecameStale];
        if (buttonIndex == 0) {
            [PsiCashClient.sharedInstance purchaseSpeedBoostProduct:purchaseAlertView.lastSKUEmitted];
        } else if (buttonIndex == 1) {
            // User hit cancel
        } else {
            // Do nothing
        }
    };

    __weak PsiCashPurchaseAlertView *weakAlertView = alertView;
    [[PsiCashClient.sharedInstance.clientModelSignal deliverOnMainThread] subscribeNext:^(PsiCashClientModel *newClientModel) {
        if (weakAlertView != nil) {
            [weakAlertView bindWithModel:newClientModel];
        }
    }];

    return alertView;
}

+ (PsiCashPurchaseAlertView*)pendingPurchaseAlert {
    PsiCashPurchaseAlertView *alertView = [[PsiCashPurchaseAlertView alloc] init];
    alertView->alreadySpeedBoosting = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 250, 150)];
    label.text = @"Buying Speed Boost...";
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    alertView.purchaseView = nil;
    alertView.containerView = label;

    alertView.buttonTitles = [NSMutableArray arrayWithObjects:@"Ok", nil];
    alertView.closeOnTouchUpOutside = YES;
    alertView.onButtonTouchUpInside = ^(CustomIOSAlertView *alertView, int buttonIndex) {
        PsiCashPurchaseAlertView *purchaseAlertView = (PsiCashPurchaseAlertView*)alertView;
        [purchaseAlertView.controllerDelegate stateBecameStale];
    };

    __weak PsiCashPurchaseAlertView *weakAlertView = alertView;
    [[PsiCashClient.sharedInstance.clientModelSignal deliverOnMainThread] subscribeNext:^(PsiCashClientModel *newClientModel) {
        if (weakAlertView != nil) {
            [weakAlertView bindWithModel:newClientModel];
        }
    }];

    return alertView;
}

+ (PsiCashPurchaseAlertView*)alreadySpeedBoostingAlertWithNMinutesRemaining:(int)minsRemaining {
    PsiCashPurchaseAlertView *alertView = [[PsiCashPurchaseAlertView alloc] init];
    alertView->alreadySpeedBoosting = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 250, 150)];
    label.text = [NSString stringWithFormat:@"%d minutes of Speed Boost remaining", minsRemaining];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    alertView.purchaseView = nil;
    alertView.containerView = label;

    alertView.buttonTitles = [NSMutableArray arrayWithObjects:@"Ok", nil];
    alertView.closeOnTouchUpOutside = YES;
    alertView.onButtonTouchUpInside = ^(CustomIOSAlertView *alertView, int buttonIndex) {
        PsiCashPurchaseAlertView *purchaseAlertView = (PsiCashPurchaseAlertView*)alertView;
        [purchaseAlertView.controllerDelegate stateBecameStale];
    };

    __weak PsiCashPurchaseAlertView *weakAlertView = alertView;
    [[PsiCashClient.sharedInstance.clientModelSignal deliverOnMainThread] subscribeNext:^(PsiCashClientModel *newClientModel) {
        if (weakAlertView != nil) {
            [weakAlertView bindWithModel:newClientModel];
        }
    }];

    return alertView;
}

#pragma mark - PsiCashSpeedBoostPurchaseReceiver protocol

- (void)targetSpeedBoostProductSKUChanged:(PsiCashSpeedBoostProductSKU *)sku {
    self.lastSKUEmitted = sku;
}

#pragma mark - PsiCashClientModelReceiver protocol

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    self.model = clientModel;
    [self.purchaseView bindWithModel:self.model];
}

@end
