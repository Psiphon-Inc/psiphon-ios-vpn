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

#define kBorderWidth 2.f
#define kDistanceFromOuterToInnerMeter 6.f

@interface InnerMeterView : UIView
@property (nonatomic, assign) CGFloat progress;
@property (nonatomic, assign) BOOL speedBoosting;
@end

@implementation InnerMeterView {
    CAShapeLayer *progressBar;
    CAGradientLayer *gradient;
    CAGradientLayer *backgroundGradient;
    PastelView *animatedGradientView;
    BOOL isRTL;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        isRTL = [UIApplication sharedApplication]
                  .userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;

        self.clipsToBounds = YES;

        // Add background gradient
        backgroundGradient = [CAGradientLayer layer];
        backgroundGradient.startPoint = CGPointMake(0, 0.5);
        backgroundGradient.endPoint = CGPointMake(1.0, 0.5);
        backgroundGradient.colors = isRTL ? @[(id)[UIColor paleGreyTwo].CGColor,
                                              (id)[UIColor lightBlueGreyTwo].CGColor]
                                          : @[(id)[UIColor lightBlueGreyTwo].CGColor,
                                             (id)[UIColor paleGreyTwo].CGColor];
        [self.layer addSublayer:backgroundGradient];
    }

    return self;
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    backgroundGradient.frame = bounds;
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

    UIRectCorner corners = isRTL ?
                                   kCALayerMaxXMinYCorner|kCALayerMaxXMaxYCorner
                                 : kCALayerMinXMinYCorner|kCALayerMinXMaxYCorner;
    if (progress == 0 || progress >= 1) {
        corners |= isRTL ?
                           kCALayerMinXMinYCorner|kCALayerMinXMaxYCorner
                         : kCALayerMaxXMaxYCorner|kCALayerMaxXMinYCorner;
    }

    if (progress >= 1) {
        animatedGradientView = [[PastelView alloc] init];
        animatedGradientView.colors = isRTL ? @[[UIColor lightSeafoam],
                                                [UIColor robinEggBlue]]
                                            : @[[UIColor robinEggBlue],
                                                [UIColor lightSeafoam]];
        [self addSubview:animatedGradientView];
        animatedGradientView.frame = self.bounds;

        progressBar.path = [UIBezierPath
                    bezierPathWithRoundedRect:CGRectMake(0,
                                                         0,
                                                         progressBarWidth,
                                                         self.frame.size.height)
                           byRoundingCorners:corners
                                 cornerRadii:CGSizeMake(progressBarRadius,
                                                        progressBarRadius)].CGPath;

        animatedGradientView.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
        [animatedGradientView startAnimation];
    } else {
        gradient = [CAGradientLayer layer];
        [self.layer insertSublayer:gradient above:backgroundGradient];

        gradient.startPoint = CGPointMake(0, 0.5);
        gradient.endPoint = CGPointMake(1.0, 0.5);
        gradient.mask = progressBar;

        gradient.colors = isRTL ? @[(id)[UIColor darkCream].CGColor,
                                    (id)[UIColor peachyPink].CGColor]
                                : @[(id)[UIColor peachyPink].CGColor,
                                    (id)[UIColor darkCream].CGColor];

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

        CGFloat gradientWidth = progress == 0 ? progressBarWidth : self.frame.size.width;
        CGFloat gradientOffset = 0;
        if (progress == 0) {
            gradientOffset = isRTL ? self.frame.size.width - progressBarWidth : 0;
        }

        gradient.frame = CGRectMake(gradientOffset, 0, gradientWidth, self.frame.size.height);
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
    NSLayoutConstraint *instantBuyButtonCenterXConstraint;
}

#pragma mark - Init

- (void)setupViews {
    self.backgroundColor = [UIColor whiteColor];
    self.clipsToBounds = YES;
    self.layer.borderColor = [UIColor duckEggBlue].CGColor;
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
    innerBackground.backgroundColor = [UIColor paleGreyTwo];
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
    NSString *text = NSLocalizedStringWithDefaultValue(@"PSICASH_BUYING_SPEED_BOOST_TEXT", nil, [NSBundle mainBundle], @"Buying Speed Boost...", @"Text which appears in the Speed Boost meter when the user's buy request for Speed Boost is being processed. Please keep this text concise as the width of the text box is restricted in size.");
    title.attributedText = [self styleTitleText:text];
}

- (NSAttributedString*)styleTitleText:(NSString*)s {
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc] initWithString:s];
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
    if (progress >= 1) {
        NSString *speedBoostAvailable = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_AVAILABLE_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Available", @"Text which appears in the Speed Boost meter when the user has earned enough PsiCash to buy Speed Boost. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.");
        if ([self.model.maxSpeedBoostPurchaseEarned.hours floatValue] < 1) {
            text = [NSString stringWithFormat:@"%.0fm %@", ([hoursEarned floatValue] * 60), speedBoostAvailable];

        } else {
            text = [NSString stringWithFormat:@"%luh %@", (unsigned long)[hoursEarned unsignedIntegerValue], speedBoostAvailable];
        }
    } else {
        NSString *speedBoostCharging = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_CHARGING_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Charging", @"Text which appears in the Speed Boost meter when the user has not yet earned enough PsiCash to Speed Boost. This text will be accompanied with a percentage indicating to the user how close they are to earning enough PsiCash to buy a minimum amount of Speed Boost. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.");
        text = [NSString stringWithFormat:@"%@ %.0f%%", speedBoostCharging, [self progressToMinSpeedBoostPurchase]*100];
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

            NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_ACTIVE_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Active", @"Text which appears in the Speed Boost meter when the user has activated Speed Boost. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
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
    NSString *text = NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_NOAUTH_TEXT", nil, [NSBundle mainBundle], @"Earn PsiCash to buy Speed Boost", @"Text which appears in the Speed Boost meter when the user has not earned any PsiCash yet. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed. Note: 'PsiCash' should not be translated or transliterated.");
    title.attributedText = [self styleTitleText:text];
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
            [self activeSpeedBoostExpiringIn:self.model.activeSpeedBoostPurchase.localTimeExpiry.timeIntervalSinceNow];
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

