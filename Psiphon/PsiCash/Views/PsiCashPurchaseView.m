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

#import "PsiCashPurchaseView.h"
#import "PsiCashBalanceView.h"
#import "PsiCashBranding.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostSliderView.h"

@interface PsiCashPurchaseView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

#pragma mark -

@implementation PsiCashPurchaseView {
    UILabel *conversionView;
    PsiCashSpeedBoostSliderView *sliderView;
    PsiCashSpeedBoostProductSKU *lastSKUEmitted;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setupViews];
        [self addViews];
        [self setupLayoutConstraints];
    }

    return self;
}

- (void)setupViews {
    conversionView = [[UILabel alloc] init];
    conversionView.adjustsFontSizeToFitWidth = YES;
    conversionView.textAlignment = NSTextAlignmentCenter;

    sliderView = [[PsiCashSpeedBoostSliderView alloc] init];
    sliderView.delegate = self;
}

- (void)addViews {
    [self addSubview:conversionView];
    [self addSubview:sliderView];
}

- (void)setupLayoutConstraints {
    conversionView.translatesAutoresizingMaskIntoConstraints = NO;
    [conversionView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [conversionView.bottomAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [conversionView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.7f].active = YES;

    sliderView.translatesAutoresizingMaskIntoConstraints = NO;
    [sliderView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [sliderView.topAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [sliderView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.7f].active = YES;
    [sliderView.heightAnchor constraintEqualToConstant:50.f].active = YES;
}

- (void)setDelegate:(id<PsiCashSpeedBoostPurchaseReceiver>)delegate {
    _delegate = delegate;
    [self notifyDelegateOfLastSKUEmitted];
}

# pragma mark - PsiCashSpeedBoostPurchaseReceiver delegate

- (void)notifyDelegateOfLastSKUEmitted {
    __strong id<PsiCashSpeedBoostPurchaseReceiver> strongDelegate = self.delegate;
    if (strongDelegate) {
        [strongDelegate targetSpeedBoostProductSKUChanged:lastSKUEmitted];
    }
}

# pragma mark - PsiCashSpeedBoostPurchaseReceiver protocol

- (void)targetSpeedBoostProductSKUChanged:(PsiCashSpeedBoostProductSKU *)sku {
    if (sku) {
        conversionView.text = [NSString stringWithFormat:@"%@ hours of %@ = %.2f %@", sku.hours, PsiCashBranding.name, [sku priceInPsi], PsiCashBranding.baseUnitName];
    } else {
        conversionView.text = @"loading...";
    }

    lastSKUEmitted = sku;

    [self notifyDelegateOfLastSKUEmitted];
}

#pragma mark - PsiCashClientModelReceiver protocol

- (void)bindWithModel:(PsiCashClientModel*)clientModel {
    self.model = clientModel;

    sliderView.hidden = NO;
    sliderView.userInteractionEnabled = YES;
    [sliderView bindWithModel:self.model];
}

@end
