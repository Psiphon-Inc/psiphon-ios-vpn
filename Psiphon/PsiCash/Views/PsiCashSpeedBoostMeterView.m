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
#import "PastelView.h"
#import "PsiCashClient.h"
#import "ReactiveObjC.h"

#define kCornerRadius 25.f
#define kBorderWidth 4.f

@interface InnerMeterView : UIView
@property (nonatomic, assign) CGFloat progress;
@property (nonatomic, assign) BOOL speedBoosting;
@end

@implementation InnerMeterView {
    CAShapeLayer *progressBar;
    CAGradientLayer *gradient;
    PastelView *animatedGradientView;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        self.clipsToBounds = YES;
    }

    return self;
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    [self updateProgressBarWithProgress:_progress];
}

- (void)setProgress:(CGFloat)progress {
    _progress = progress;
    [self updateProgressBarWithProgress:_progress];
}

- (void)updateProgressBarWithProgress:(CGFloat)progress {
    [self removeProgressBar];

    progressBar = [CAShapeLayer layer];


    CGFloat progressBarRadius = kCornerRadius;
    CGFloat progressBarWidth = self.frame.size.width * progress;

    UIRectCorner corners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    if (progress == 0 || progress >= 1) {
        corners |= kCALayerMaxXMaxYCorner | kCALayerMaxXMinYCorner;
    }

    if (progress >= 1) {
        animatedGradientView = [[PastelView alloc] init];
        if (_speedBoosting) {
            animatedGradientView.colors = @[[UIColor colorWithRed:0.50 green:0.49 blue:1.00 alpha:1.0],
                                            [UIColor colorWithRed:0.62 green:0.38 blue:1.00 alpha:1.0]];
        }
        [self addSubview:animatedGradientView];
        animatedGradientView.frame = self.bounds;

        progressBar.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, progressBarWidth, self.frame.size.height) byRoundingCorners:corners cornerRadii:CGSizeMake(progressBarRadius, progressBarRadius)].CGPath;
        animatedGradientView.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
        [animatedGradientView startAnimation];
    } else {
        gradient = [CAGradientLayer layer];
        [self.layer insertSublayer:gradient atIndex:0];
        gradient.startPoint = CGPointMake(0, 0.5);
        gradient.endPoint = CGPointMake(1.0, 0.5);
        gradient.mask = progressBar;

        gradient.colors = @[(id)[UIColor colorWithRed:0.16 green:0.38 blue:1.00 alpha:1.0].CGColor, (id)[UIColor colorWithRed:0.55 green:0.72 blue:1.00 alpha:1.0].CGColor];
        progressBar.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, progressBarWidth, self.frame.size.height) byRoundingCorners:corners cornerRadii:CGSizeMake(progressBarRadius, progressBarRadius)].CGPath;
        gradient.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
    }
}

- (void)removeProgressBar {
    [progressBar removeFromSuperlayer];
    progressBar = nil;
    [gradient removeFromSuperlayer];
    gradient = nil;
    [animatedGradientView removeFromSuperview];
    animatedGradientView = nil;
}

@end


@interface PsiCashSpeedBoostMeterView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

@implementation PsiCashSpeedBoostMeterView {
    UILabel *title;
    NSTimer *countdownToNextHourExpired;
    UIImageView *instantBuyButton;
    InnerMeterView *innerBackground;
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
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;
    self.layer.borderWidth = kBorderWidth;
    self.layer.borderColor = [UIColor colorWithWhite:0 alpha:.12].CGColor;

    instantBuyButton = [[UIImageView alloc] initWithFrame:CGRectMake(60, 95, 90, 90)];
    instantBuyButton.image = [UIImage imageNamed:@"PsiCash_InstantPurchaseButton"];
    [instantBuyButton.layer setMinificationFilter:kCAFilterTrilinear];

    title = [[UILabel alloc] init];
    title.adjustsFontSizeToFitWidth = YES;
    title.font = [UIFont boldSystemFontOfSize:14];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = [UIColor colorWithRed:0.98 green:0.99 blue:1.00 alpha:1.0];

    innerBackground = [[InnerMeterView alloc] init];
    innerBackground.backgroundColor = [UIColor colorWithWhite:0 alpha:.24];
    innerBackground.layer.cornerRadius = kCornerRadius - kBorderWidth;
}

- (void)addViews {
    [self addSubview:innerBackground];
    [self addSubview:instantBuyButton];
    [self addSubview:title];
}

- (void)setupLayoutConstraints {
    innerBackground.translatesAutoresizingMaskIntoConstraints = NO;
    [innerBackground.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-kBorderWidth*2].active = YES;
    [innerBackground.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:-kBorderWidth*2].active = YES;
    [innerBackground.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [innerBackground.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

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
    [title.leadingAnchor constraintEqualToAnchor:instantBuyButton.trailingAnchor].active = YES;
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
    [innerBackground setSpeedBoosting:NO];
    [innerBackground setProgress:progress];

    if (progress >= 1) {
        if ([self.model.maxSpeedBoostPurchaseEarned.hours floatValue] < 1) {
            title.text = [NSString stringWithFormat:@"%.0fm Speed Boost Available", ([hoursEarned floatValue] * 60)];
        } else {
            title.text = [NSString stringWithFormat:@"%luh Speed Boost Available", (unsigned long)[hoursEarned unsignedIntegerValue]];
        }
    } else {
        title.text = [NSString stringWithFormat:@"Speed Boost Charging %.0f%%", [self progressToMinSpeedBoostPurchase]*100];
    }
}

- (void)activeSpeedBoostExpiringIn:(NSTimeInterval)seconds {
    [innerBackground setSpeedBoosting:YES];
    [innerBackground setProgress:1];

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

    float progress = (float)self.model.balanceInNanoPsi / [sku.price unsignedLongLongValue];
    if (progress > 1) {
        progress = 1;
    }

    return progress;
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

