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
#import "Logging.h"
#import "PastelView.h"
#import "PsiCashClient.h"
#import "ReactiveObjC.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"
#import "UIView+AutoLayoutViewGroup.h"
#import "Strings.h"

#define kBorderWidth 2.f
#define kDistanceFromOuterToInnerMeter 6.f

@interface InnerMeterView : UIView
@property (nonatomic, assign) CGFloat progress;
@property (nonatomic, assign) BOOL speedBoosting;
@end

@implementation InnerMeterView {
    CAShapeLayer *progressBar;
    CAGradientLayer *gradient;
    BOOL isRTL;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        isRTL = [UIApplication sharedApplication]
                  .userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;

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

    CGFloat progressBarRadius = self.frame.size.height / 2;
    CGFloat progressBarWidth = self.frame.size.width * progress;

    UIRectCorner corners = isRTL ? UIRectCornerBottomRight|UIRectCornerTopRight
                                 : UIRectCornerBottomLeft|UIRectCornerTopLeft;

    if (progress == 0 || progress >= 1) {
        corners = UIRectCornerAllCorners;
    }

    if (progress == 0) {
        // Make a bubble over the speed boost icon
        progressBarWidth = progressBarRadius * 2;
    }

    CGFloat progressBarOffset = isRTL ? self.frame.size.width  - progressBarWidth : 0;
    if (progress == 0) {
        progressBarOffset = 0;
    }

    progressBar.path = [UIBezierPath
      bezierPathWithRoundedRect:CGRectMake(progressBarOffset,
        0,
        progressBarWidth,
        self.frame.size.height)
              byRoundingCorners:corners
                    cornerRadii:CGSizeMake(progressBarRadius,
                      progressBarRadius)].CGPath;

    gradient = [CAGradientLayer layer];
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint = CGPointMake(1.0, 0.5);
    gradient.mask = progressBar;

    CGFloat gradientWidth = progress == 0 ? progressBarWidth : self.frame.size.width;
    CGFloat gradientOffset = 0;
    if (progress == 0) {
        gradientOffset = isRTL ? self.frame.size.width - progressBarWidth : 0;
    }

    gradient.frame = CGRectMake(gradientOffset, 0, gradientWidth, self.frame.size.height);

    if (progress >= 1) {
        gradient.colors = isRTL ? @[(id)[UIColor lightSeafoamColor].CGColor, (id)[UIColor robinEggBlueColor].CGColor]
                                : @[(id)[UIColor robinEggBlueColor].CGColor, (id)[UIColor lightSeafoamColor].CGColor];
    } else {
        gradient.colors = isRTL ? @[(id)[UIColor darkCream].CGColor,
                                    (id)[UIColor peachyPink].CGColor]
                                : @[(id)[UIColor peachyPink].CGColor,
                                    (id)[UIColor darkCream].CGColor];
    }

    [self.layer addSublayer:gradient];
}

- (void)removeProgressBar {
    [progressBar removeFromSuperlayer];
    progressBar = nil;
    [gradient removeFromSuperlayer];
    gradient = nil;
}

@end


@interface PsiCashSpeedBoostMeterView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

@implementation PsiCashSpeedBoostMeterView {
    UILabel *title;
    NSTimer *countdownToSpeedBoostExpiry;
    UIImageView *instantBuyButton;
    InnerMeterView *innerBackground;
    NSLayoutConstraint *instantBuyButtonCenterXConstraint;
}

#pragma mark - Init

- (void)setupViews {
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = YES;
    self.layer.borderColor = UIColor.denimBlueColor.CGColor;
    self.layer.borderWidth = kBorderWidth;

    instantBuyButton = [[UIImageView alloc] initWithFrame:CGRectMake(60, 95, 90, 90)];
    instantBuyButton.image = [UIImage imageNamed:@"PsiCash_InstantPurchaseButton"];
    [instantBuyButton.layer setMinificationFilter:kCAFilterTrilinear];

    title = [[UILabel alloc] init];
    title.adjustsFontSizeToFitWidth = YES;
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont avenirNextBold:12.f];

    innerBackground = [[InnerMeterView alloc] init];
    innerBackground.backgroundColor = UIColor.regentGrey;
}

- (void)addSubviews {
    [self addSubview:innerBackground];
    [self addSubview:instantBuyButton];
    [self addSubview:title];
}

- (void)setupSubviewsLayoutConstraints {
    innerBackground.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat distanceFromOuterMeterBorderToInnerMeter = kBorderWidth + kDistanceFromOuterToInnerMeter;
    [innerBackground.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-distanceFromOuterMeterBorderToInnerMeter*2].active = YES;
    [innerBackground.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:-distanceFromOuterMeterBorderToInnerMeter*2].active = YES;
    [innerBackground.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [innerBackground.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

    instantBuyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [instantBuyButton.widthAnchor constraintEqualToAnchor:instantBuyButton.heightAnchor].active = YES;
    [instantBuyButton.heightAnchor constraintEqualToAnchor:innerBackground.heightAnchor multiplier:.5].active = YES;
    [self updateInstantBuyButtonCenterXConstraint];
    [instantBuyButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    instantBuyButton.contentMode = UIViewContentModeScaleAspectFit;

    title.translatesAutoresizingMaskIntoConstraints = NO;
    [title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [title.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [title.leadingAnchor constraintEqualToAnchor:instantBuyButton.trailingAnchor constant:20].active = YES;
}

#pragma mark - View sizing

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    self.layer.cornerRadius = bounds.size.height / 2;
    innerBackground.layer.cornerRadius = [self innerCornerRadius];
    [self updateInstantBuyButtonCenterXConstraint];
}

- (CGFloat)innerCornerRadius {
    return self.layer.cornerRadius - kBorderWidth - kDistanceFromOuterToInnerMeter;
}

- (void)updateInstantBuyButtonCenterXConstraint {
    if (instantBuyButtonCenterXConstraint) {
        instantBuyButtonCenterXConstraint.active = NO;
    }
    CGFloat offset = self.layer.cornerRadius - kBorderWidth - kDistanceFromOuterToInnerMeter;
    instantBuyButtonCenterXConstraint = [instantBuyButton.centerXAnchor constraintEqualToAnchor:innerBackground.leadingAnchor constant:offset];
    instantBuyButtonCenterXConstraint.active = YES;
}

#pragma mark - State Changes

- (void)inPurchasePendingState {
    title.attributedText = [self styleTitleText:[Strings psiCashSpeedBoostMeterBuyingTitle]];
}

- (NSAttributedString*)styleTitleText:(NSString*)s {
    NSString *upperCased = [s localizedUppercaseString];
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc]
      initWithString:upperCased];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [UIColor colorWithWhite:0 alpha:.12];
    shadow.shadowBlurRadius = 8.0;
    shadow.shadowOffset = CGSizeMake(0, 2);
    NSDictionary *attr = @{NSShadowAttributeName:shadow};
    [mutableStr setAttributes:attr range:NSMakeRange(0, mutableStr.length)];

    [mutableStr addAttribute:NSKernAttributeName
                       value:@1.1
                       range:NSMakeRange(0, mutableStr.length)];

    return mutableStr;
}

- (void)speedBoostChargingWithHoursEarned:(NSNumber*)hoursEarned {
    float progress = [self progressToMinSpeedBoostPurchase];
    [innerBackground setSpeedBoosting:NO];
    [innerBackground setProgress:progress];

    NSString *text;
    if (!self.model.onboarded) {
        text = [Strings psiCashSpeedBoostMeterUserNotOnboardedTitle];
    } else if (progress >= 1) {
        NSString *speedBoostAvailable = [Strings psiCashSpeedBoostMeterAvailableTitle];
        if ([self.model.maxSpeedBoostPurchaseEarned.hours floatValue] < 1) {
            text = [NSString stringWithFormat:@"%.0fm %@", ([hoursEarned floatValue] * 60), speedBoostAvailable];

        } else {
            text = [NSString stringWithFormat:@"%luh %@", (unsigned long)[hoursEarned unsignedIntegerValue], speedBoostAvailable];
        }
    } else {
        text = [NSString stringWithFormat:@"%@ %.0f%%",
          [Strings psiCashSpeedBoostMeterChargingTitle],
          [self progressToMinSpeedBoostPurchase]*100];
    }
    title.attributedText = [self styleTitleText:text];
}

- (void)activeSpeedBoostExpiringIn:(NSTimeInterval)seconds {
    [innerBackground setSpeedBoosting:YES];
    [innerBackground setProgress:1];

    dispatch_async(dispatch_get_main_queue(), ^{
        countdownToSpeedBoostExpiry = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            NSTimeInterval secondsToExpiry = self.model.activeSpeedBoostPurchase.localTimeExpiry.timeIntervalSinceNow;

            if (secondsToExpiry < 0) {
                [timer invalidate];
                [self speedBoostChargingWithHoursEarned:[self.model maxSpeedBoostPurchaseEarned].hours];
                return;
            }

            int h = (int)secondsToExpiry / 3600;
            int m = (int)secondsToExpiry / 60 % 60;
            int s = (int)secondsToExpiry % 60;

            NSString *timeRemaining;
            if (h > 0) {
                timeRemaining = [NSString stringWithFormat:@"%ih %im", h, m];
            } else if (m > 0) {
                timeRemaining = [NSString stringWithFormat:@"%im %is", m, s];
            } else {
                timeRemaining = [NSString stringWithFormat:@"%is", s];
            }

            NSString *speedBoostActive = [NSString stringWithFormat:@"%@ - %@",
                                                   [Strings psiCashSpeedBoostMeterActiveTitle], timeRemaining];

            title.attributedText = [self styleTitleText:speedBoostActive];
        }];
        [countdownToSpeedBoostExpiry fire];
    });
}

#pragma mark - Helpers

- (void)noSpenderToken {
    if (self.model.onboarded) {
        title.attributedText = [self styleTitleText:[Strings psiCashSpeedBoostMeterNoAuthTitle]];
    } else {
        title.attributedText = [self styleTitleText:[Strings psiCashSpeedBoostMeterUserNotOnboardedTitle]];
    }
}


- (NSTimeInterval)timeToNextHourExpired:(NSTimeInterval)seconds {
    NSTimeInterval secondsRemaining = seconds;
    NSInteger hoursRemaining = secondsRemaining / (60 * 60);
    NSTimeInterval secondsToNextHourExpired = secondsRemaining - (hoursRemaining * 60);
    return secondsToNextHourExpired;
}

- (float)progressToMinSpeedBoostPurchase {
    PsiCashSpeedBoostProductSKU *sku = [self.model minSpeedBoostPurchaseAvailable];
    if (sku == nil) {
        return 0;
    }

    float progress = (float)self.model.balance.floatValue / sku.price.floatValue;
    if (progress > 1) {
        progress = 1;
    }

    return progress;
}

#pragma mark - PsiCashClientModelReceiver protocol

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    self.model = clientModel;

    if (countdownToSpeedBoostExpiry != nil) {
        LOG_DEBUG(@"%s invalidating timer", __FUNCTION__);
        [countdownToSpeedBoostExpiry invalidate];
    }

    if ([self.model hasAuthPackage]) {

        if ([self.model hasActiveSpeedBoostPurchase]) {
            // Active state
            [self activeSpeedBoostExpiringIn:self.model.activeSpeedBoostPurchase.localTimeExpiry.timeIntervalSinceNow];
        } else if ([self.model hasPendingPurchase]){
            // Active state
            [self inPurchasePendingState];
        } else {
            // Passive state
            if ([self.model.authPackage hasSpenderToken]) {
                [self speedBoostChargingWithHoursEarned:[self.model maxSpeedBoostPurchaseEarned].hours];
            } else {
                [self noSpenderToken];
            }
        }
    } else {
        // Disabled state
        [self noSpenderToken];
    }
}

@end

