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

#import "PsiCashSpeedBoostSliderView.h"
#import "Logging.h"
#import <math.h>

@interface PsiCashSpeedBoostSliderView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

#pragma mark -

@implementation PsiCashSpeedBoostSliderView {
    UISlider *slider;
    PsiCashSpeedBoostProductSKU *lastSKUEmitted;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setupViews];
        [self addViews];
        [self setupLayoutConstraints];
        [self startObserving];
    }

    return self;
}

- (void)setupViews {
    slider = [[UISlider alloc] init];
    slider.minimumValue = 0;
    slider.maximumValue = 0;
    slider.value = 0;
}

- (void)addViews {
    [self addSubview:slider];
}

- (void)setupLayoutConstraints {
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    [slider.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [slider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [slider.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.7f].active = YES;
    [slider.heightAnchor constraintEqualToAnchor:self.heightAnchor].active = YES;
}

- (void)startObserving {
    [slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
}

- (void)setDelegate:(id<PsiCashSpeedBoostPurchaseReceiver>)delegate {
    _delegate = delegate;
    [self sliderValueChanged:nil];
}

- (void)sliderValueChanged:(id)sender {
    NSArray<PsiCashSpeedBoostProductSKU*>* skus = self.model.speedBoostProduct.skusOrderedByPriceAscending;
    if (skus.count == 0 || slider.maximumValue == 0) {
        // no SKUs to emit
        lastSKUEmitted = nil;
        __strong id<PsiCashSpeedBoostPurchaseReceiver> strongDelegate = self.delegate;
        if (strongDelegate) {
            [strongDelegate targetSpeedBoostProductSKUChanged:nil];
        }
        return;
    }

    NSInteger index = 0;
    if ([sender isKindOfClass:[UISlider class]]) {
        index = (NSInteger) lroundf([(UISlider*)sender value]);
    } else {
        index = (NSInteger) lroundf(slider.value);
    }

    if (index < 0 ) {
        LOG_WARN(@"%s slider value was %f which is negative. Recovering by settings index to 0.", __FUNCTION__, slider.value);
        index = 0;
    }

    if (index == slider.maximumValue) {
        index = slider.maximumValue - 1;
    } else if (index > slider.maximumValue) {
        LOG_WARN(@"%s index value of %ld is greater than slider.maximumValue of %f. Recovering by setting index to slider.maximumvalue-1.", __FUNCTION__, (long)index, slider.maximumValue);
        index = slider.maximumValue - 1;
    }

    if (index >= skus.count) {
        LOG_WARN(@"%s index value of %ld is greater than number of available skus %lu. Recovering by settings index to skus.count-1.", __FUNCTION__, (long)index, (unsigned long)[skus count]);
        index = skus.count - 1;
    }

    PsiCashSpeedBoostProductSKU *sku = [skus objectAtIndex:index];

    // Only notify delegate on SKU change
    if (lastSKUEmitted != sku) {
        lastSKUEmitted = sku;
        __strong id<PsiCashSpeedBoostPurchaseReceiver> strongDelegate = self.delegate;
        if (strongDelegate) {
            [strongDelegate targetSpeedBoostProductSKUChanged:sku];
        }
    }
}

#pragma mark - PsiCashClientReceiver protocol

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    self.model = clientModel;

    slider.minimumValue = 0;
    slider.maximumValue = clientModel.speedBoostProduct.skusOrderedByPriceAscending.count;

    // Always emit a new SKU when the model changes
    [self sliderValueChanged:nil];
}

@end
