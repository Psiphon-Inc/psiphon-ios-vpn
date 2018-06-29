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

    alertView.buttonTitles = [NSMutableArray arrayWithObjects:NSLocalizedStringWithDefaultValue(@"BUY_BUTTON", nil, [NSBundle mainBundle], @"Buy", @"Alert buy button"), NSLocalizedStringWithDefaultValue(@"CANCEL_BUTTON", nil, [NSBundle mainBundle], @"Cancel", @"Alert Cancel button"), nil];
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
    label.text = NSLocalizedStringWithDefaultValue(@"PSICASH_BUYING_SPEED_BOOST_TEXT", nil, [NSBundle mainBundle], @"Buying Speed Boost...", @"Text which appears in the Speed Boost meter when the user's buy request for Speed Boost is being processed. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.");
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    alertView.purchaseView = nil;
    alertView.containerView = label;

    alertView.buttonTitles = [NSMutableArray arrayWithObjects:NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"Alert OK Button"), nil];
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

+ (PsiCashPurchaseAlertView*)alreadySpeedBoostingAlert {
    PsiCashPurchaseAlertView *alertView = [[PsiCashPurchaseAlertView alloc] init];
    alertView->alreadySpeedBoosting = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 250, 150)];
    label.text = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_ACTIVE_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Active", @"Text which appears in the Speed Boost meter when the user has activated Speed Boost. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.");
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    alertView.purchaseView = nil;
    alertView.containerView = label;

    alertView.buttonTitles = [NSMutableArray arrayWithObjects:NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"Alert OK Button"), nil];
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
