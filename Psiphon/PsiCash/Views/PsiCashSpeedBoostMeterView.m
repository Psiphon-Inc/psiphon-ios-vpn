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

#import "PsiCashSpeedBoostMeterView.h"
#import "PsiCashClient.h"
#import "ReactiveObjC.h"

#define kCornerRadius 25.f

@interface PsiCashSpeedBoostMeterView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

#pragma mark -

@implementation PsiCashSpeedBoostMeterView {
    UILabel *title;
    NSTimer *countdownToNextHourExpired;
    UIImageView *instantBuyButton;

    // Progress bar
    CAShapeLayer *progressBar;
    CAGradientLayer *gradient;
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
    self.layer.cornerRadius = kCornerRadius;
    self.clipsToBounds = YES;
    self.backgroundColor = [UIColor colorWithRed:0.16 green:0.18 blue:0.27 alpha:1.0];
    self.layer.borderWidth = 4.f;
    self.layer.borderColor = [UIColor colorWithRed:0.29 green:0.31 blue:0.40 alpha:1.0].CGColor;

    instantBuyButton = [[UIImageView alloc] initWithFrame:CGRectMake(60, 95, 90, 90)];
    instantBuyButton.image = [UIImage imageNamed:@"PsiCash_InstantPurchaseButton"];
    [instantBuyButton.layer setMinificationFilter:kCAFilterTrilinear];

    title = [[UILabel alloc] init];
    title.adjustsFontSizeToFitWidth = YES;
    title.font = [UIFont boldSystemFontOfSize:14];
    title.textColor = [UIColor colorWithRed:0.98 green:0.99 blue:1.00 alpha:1.0];
}

- (void)addViews {
    [self addSubview:instantBuyButton];
    [self addSubview:title];
}

- (void)setupLayoutConstraints {
    CGFloat instantBuyButtonSize = 20.f;
    instantBuyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [instantBuyButton.heightAnchor constraintEqualToConstant:instantBuyButtonSize].active = YES;
    [instantBuyButton.widthAnchor constraintEqualToConstant:instantBuyButtonSize].active = YES;
    [instantBuyButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [instantBuyButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.f].active = YES;
    instantBuyButton.contentMode = UIViewContentModeScaleAspectFit;

    title.translatesAutoresizingMaskIntoConstraints = NO;
    [title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [title.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
}

# pragma mark - State Changes

- (void)inRetrievingAuthPackageState {
    title.text = @"...";
}

- (void)inPurchasePendingState {
    title.text = @"Buying Speed Boost...";
}

- (void)speedBoostChargingWithHoursEarned:(NSNumber*)hoursEarned {
    float progress = [self progressToMinSpeedBoostPurchase];
    [self addProgressBarWithProgress:progress];
    self.backgroundColor = [UIColor colorWithRed:0.16 green:0.18 blue:0.27 alpha:1.0];

    if (progress >= 1) {
        if ([self.model.maxSpeedBoostPurchaseEarned.hours floatValue] < 1) {
            title.text = [NSString stringWithFormat:@"%.0fm Speed Boost Available", ([hoursEarned floatValue] * 60)];
        } else {
            title.text = [NSString stringWithFormat:@"%luh Speed Boost Available", (unsigned long)[hoursEarned unsignedIntegerValue]];
        }
    } else {
        title.attributedText = [self minSpeedBoostPurchaseTitle];
    }
}

- (void)activeSpeedBoostExpiringIn:(NSTimeInterval)seconds {
    [self removeProgressBar];
    self.backgroundColor = [UIColor colorWithRed:0.19 green:0.93 blue:0.88 alpha:1.0];

    if (seconds > 0) {
        title.text = @"Speed Boost Active";
        dispatch_async(dispatch_get_main_queue(), ^{
            countdownToNextHourExpired = [NSTimer scheduledTimerWithTimeInterval:[self timeToNextHourExpired:seconds] repeats:NO block:^(NSTimer * _Nonnull timer) {
                [self activeSpeedBoostExpiringIn:self.model.activeSpeedBoostPurchase.expiry.timeIntervalSinceNow];
            }];
        });
    } else {
        [self speedBoostChargingWithHoursEarned:[self.model maxSpeedBoostPurchaseEarned].hours];
    }
}

#pragma mark - Helpers

- (void)addProgressBarWithProgress:(float)progress {
    [self removeProgressBar];

    progressBar = [CAShapeLayer layer];
    gradient = [CAGradientLayer layer];
    [self.layer insertSublayer:gradient atIndex:0];
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint = CGPointMake(1.0, 0.5);
    gradient.mask = progressBar;

    CGFloat progressBarWidth;
    CGFloat progressBarRadius = progress == 0 ? kCornerRadius : 0;
    progressBarWidth = 2 * progressBarRadius + (self.frame.size.width - 2 * progressBarRadius) * progress;
    gradient.colors = @[(id)[UIColor colorWithRed:0.11 green:0.27 blue:0.69 alpha:1.0].CGColor, (id)[UIColor colorWithRed:0.19 green:0.93 blue:0.88 alpha:1.0].CGColor]; // green gradient
    progressBar.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, progressBarWidth, self.frame.size.height) cornerRadius:progressBarRadius].CGPath;
    gradient.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
}

- (void)removeProgressBar {
    [progressBar removeFromSuperlayer];
    progressBar = nil;
    [gradient removeFromSuperlayer];
    gradient = nil;
}

- (void)noSpenderToken {
    title.text = @"Earn PsiCash to buy Speed Boost";
}

- (NSTimeInterval)timeToNextHourExpired:(NSTimeInterval)seconds {
    NSTimeInterval secondsRemaining = seconds;
    NSInteger hoursRemaining = secondsRemaining / (60 * 60);
    NSTimeInterval secondsToNextHourExpired = secondsRemaining - (hoursRemaining * 60);
    return secondsToNextHourExpired;
}

- (NSAttributedString*)minSpeedBoostPurchaseTitle {
    PsiCashSpeedBoostProductSKU *sku = [self.model minSpeedBoostPurchaseAvailable];
    if (sku == nil) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    NSString *str;
    if ([sku.hours doubleValue] < 1) {
        str = [NSString stringWithFormat:@"%dm Speed Boost at ", (int)([sku.hours doubleValue] * 60)];
    } else {
        str = [NSString stringWithFormat:@"%ldh Speed Boost at", (long)[sku.hours integerValue]];
    }

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:str];

    NSTextAttachment *imageAttachment = [[NSTextAttachment alloc] init];
    imageAttachment.image = [UIImage imageNamed:@"PsiCash_Coin"];
    imageAttachment.bounds = CGRectMake(2, -4, 16, 16);

    NSAttributedString *imageString = [NSAttributedString attributedStringWithAttachment:imageAttachment];
    [attr appendAttributedString:imageString];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %.0f", [sku priceInPsi]]]];

    return attr;
}

- (float)progressToMinSpeedBoostPurchase {
    PsiCashSpeedBoostProductSKU *sku = [self.model minSpeedBoostPurchaseAvailable];
    if (sku == nil) {
        return 0;
    }

    return (float)self.model.balanceInNanoPsi / [sku.price unsignedLongLongValue];
}

#pragma mark - PsiCashClientModelReceiver protocol

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    self.model = clientModel;

    if (countdownToNextHourExpired != nil) {
        NSLog(@"ExpiringPurchases: invalidating timer");
        [countdownToNextHourExpired invalidate];
    }

    if ([self.model hasAuthPackage]) {
        if ([self.model hasActiveSpeedBoostPurchase]) {
            [self activeSpeedBoostExpiringIn:self.model.activeSpeedBoostPurchase.expiry.timeIntervalSinceNow];
        } else if ([self.model hasPendingPurchase]){
            [self inPurchasePendingState];
        } else {
            if ([self.model.authPackage hasSpenderToken]) {
                [self speedBoostChargingWithHoursEarned:[self.model maxSpeedBoostPurchaseEarned].hours];
            } else {
                [self noSpenderToken];
            }
        }
    } else {
        [self inRetrievingAuthPackageState];
    }
}

@end

