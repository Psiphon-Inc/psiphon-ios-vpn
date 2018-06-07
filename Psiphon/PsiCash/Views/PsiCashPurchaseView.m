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
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostSliderView.h"
#import "PsiCashErrorTypes.h"
#import "PsiFeedbackLogger.h"

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
    [sliderView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.9f].active = YES;
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
        NSString *formatString;

        if ([sku.hours doubleValue] < 1) {
            // TODO: (1.0) DEBUG only
            formatString = NSLocalizedStringWithDefaultValue(@"PSICASH_CONVERSION_MINS_MESSAGE", nil, [NSBundle mainBundle], @"%d minutes of Speed Boost at", @"Text conveying to the user how much the displayed number of hours of Speed Boost costs. %@ should be not be removed but placed in the appropriate location because it will be replaced with the number of hours programmatically. After this sentence the cost of the Speed Boost item will be displayed. For example '5 mins of Speed Boost at 25'." );
        } else if ([sku.hours doubleValue] == 1) {
            formatString = NSLocalizedStringWithDefaultValue(@"PSICASH_CONVERSION_HOUR_MESSAGE", nil, [NSBundle mainBundle], @"%@ hour of Speed Boost at", @"Text conveying to the user how much the displayed number of hours of Speed Boost costs. %@ should be not be removed but placed in the appropriate location because it will be replaced with the number of hours programmatically. After this sentence the cost of the Speed Boost item will be displayed. For example '1 hour of Speed Boost at 50'." );
        } else {
            formatString = NSLocalizedStringWithDefaultValue(@"PSICASH_CONVERSION_HOURS_MESSAGE", nil, [NSBundle mainBundle], @"%@ hours of Speed Boost at", @"Text conveying to the user how much the displayed number of hours of Speed Boost costs. %@ should be not be removed but placed in the appropriate location because it will be replaced with the number of hours programmatically. After this sentence the cost of the Speed Boost item will be displayed. For example '2 hours of Speed Boost at 100'." );
        }
        [formatString stringByAppendingString:@" "];

        NSString *str;
        if ([sku.hours doubleValue] < 1) {
            // TODO: (1.0) DEBUG only
            str = [NSString stringWithFormat:formatString, (int)([sku.hours doubleValue] * 60)];
        } else {
            str = [NSString stringWithFormat:formatString, sku.hours];
        }

        NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:str];

        NSTextAttachment *imageAttachment = [[NSTextAttachment alloc] init];
        imageAttachment.image = [UIImage imageNamed:@"PsiCash_Coin"];
        imageAttachment.bounds = CGRectMake(2, -4, 16, 16);

        NSAttributedString *imageString = [NSAttributedString attributedStringWithAttachment:imageAttachment];
        [attr appendAttributedString:imageString];
        [attr appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %.0f", [sku priceInPsi]]]];
        conversionView.attributedText = attr;
    } else {
        // TOOD: (1.0) replace this with conversionView.text = @""
        // This should never be seen
        conversionView.text = NSLocalizedStringWithDefaultValue(@"PSICASH_LOADING_SPEED_BOOST_PRODUCTS_MESSAGE", nil, [NSBundle mainBundle], @"Loading Speed Boost product...", @"Text conveying to the user that the target Speed Boost product is being loaded");
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
