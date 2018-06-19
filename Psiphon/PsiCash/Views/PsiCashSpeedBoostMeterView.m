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
    NSTimer *countdownToSpeedBoostExpiry;
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

- (void)inPurchasePendingState {
    title.text = NSLocalizedStringWithDefaultValue(@"PSICASH_BUYING_SPEED_BOOST_TEXT", nil, [NSBundle mainBundle], @"Buying Speed Boost...", @"Text which appears in the Speed Boost meter when the user's buy request for Speed Boost is being processed. Please keep this text concise as the width of the text box is restricted in size.");
}

- (void)speedBoostChargingWithHoursEarned:(NSNumber*)hoursEarned {
    float progress = [self progressToMinSpeedBoostPurchase];
    [innerBackground setSpeedBoosting:NO];
    [innerBackground setProgress:progress];

    if (progress >= 1) {
        NSString *speedBoostAvailable = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_AVAILABLE_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Available", @"Text which appears in the Speed Boost meter when the user has earned enough PsiCash to buy Speed Boost. Please keep this text concise as the width of the text box is restricted in size.");
        if ([self.model.maxSpeedBoostPurchaseEarned.hours floatValue] < 1) {
            title.text = [NSString stringWithFormat:@"%.0fm %@", ([hoursEarned floatValue] * 60), speedBoostAvailable];
        } else {
            title.text = [NSString stringWithFormat:@"%luh %@", (unsigned long)[hoursEarned unsignedIntegerValue], speedBoostAvailable];
        }
    } else {
        NSString *speedBoostCharging = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_CHARGING_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Charging", @"Text which appears in the Speed Boost meter when the user has not yet earned enough PsiCash to Speed Boost. This text will be accompanied with a percentage indicating to the user how close they are to earning enough PsiCash to buy a minimum amount of Speed Boost. Please keep this text concise as the width of the text box is restricted in size.");
        title.text = [NSString stringWithFormat:@"%@ %.0f%%", speedBoostCharging, [self progressToMinSpeedBoostPurchase]*100];
    }
}

- (void)activeSpeedBoostExpiringIn:(NSTimeInterval)seconds {
    [innerBackground setSpeedBoosting:YES];
    [innerBackground setProgress:1];

    dispatch_async(dispatch_get_main_queue(), ^{
        countdownToSpeedBoostExpiry = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            NSTimeInterval secondsToExpiry = self.model.activeSpeedBoostPurchase.expiry.timeIntervalSinceNow;

            if (secondsToExpiry < 0) {
                [timer invalidate];
                [self speedBoostChargingWithHoursEarned:[self.model maxSpeedBoostPurchaseEarned].hours];
                return;
            }

            int h = (int)secondsToExpiry / 3600;
            int m = (int)secondsToExpiry / 60 % 60;
            int s = (int)secondsToExpiry % 60;

            NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_ACTIVE_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Active", @"Text which appears in the Speed Boost meter when the user has activated Speed Boost. Please keep this text concise as the width of the text box is restricted in size.")
                                                                                     attributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:14]}];
            NSAttributedString *timeRemaining;

            [attr appendAttributedString:[[NSAttributedString alloc] initWithString:@" - "]];
            NSDictionary *timeRemainingAttributes = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:14]};
            if (h > 0) {
                timeRemaining = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%ih %im", h, m] attributes:timeRemainingAttributes];
            } else if (m > 0) {
                timeRemaining = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%im %is", m, s] attributes:timeRemainingAttributes];
            } else {
                timeRemaining = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%is", s] attributes:timeRemainingAttributes];
            }

            [attr appendAttributedString:timeRemaining];
            title.attributedText = attr;
        }];
        [countdownToSpeedBoostExpiry fire];
    });
}

#pragma mark - Helpers

- (void)noSpenderToken {
    title.text = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_NOAUTH_TEXT", nil, [NSBundle mainBundle], @"Earn PsiCash to buy Speed Boost", @"Text which appears in the Speed Boost meter when the user has not earned any PsiCash yet. Please keep this text concise as the width of the text box is restricted in size.");
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
        [self noSpenderToken];
    }
}

@end

