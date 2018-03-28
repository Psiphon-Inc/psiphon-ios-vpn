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

#define kCornerRadius 10.f

@interface PsiCashSpeedBoostMeterView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

#pragma mark -

@implementation PsiCashSpeedBoostMeterView {
    UILabel *title;
    UILabel *hoursLabel;
    CGFloat progressToNextHour;
    NSTimer *countdownToNextHourExpired;
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
    self.backgroundColor = [UIColor colorWithRed:0.26 green:0.54 blue:0.85 alpha:1.0];
    self.layer.borderColor = [UIColor colorWithRed:0.53 green:0.57 blue:0.62 alpha:1.0].CGColor;
    self.layer.borderWidth = 1.5f;
    self.layer.cornerRadius = kCornerRadius;

    title = [[UILabel alloc] init];
    title.adjustsFontSizeToFitWidth = YES;
    title.font = [UIFont systemFontOfSize:12.f];
    title.textColor = [UIColor colorWithRed:0.98 green:0.99 blue:1.00 alpha:1.0];

    hoursLabel = [[UILabel alloc] init];
    hoursLabel.adjustsFontSizeToFitWidth = YES;
    hoursLabel.font = [UIFont systemFontOfSize:8.f];
    hoursLabel.textColor = [UIColor colorWithRed:0.98 green:0.99 blue:1.00 alpha:1.0];
}

- (void)addViews {
    [self addSubview:title];
    [self addSubview:hoursLabel];
}

- (void)setupLayoutConstraints {
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [title.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

    hoursLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [hoursLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [hoursLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kCornerRadius].active = YES;
}

# pragma mark - Helpers

- (void)inRetrievingAuthPackageState {
    title.text = @"...";
    hoursLabel.text = @"";
}

- (void)inPurchasePendingState {
    title.text = @"Purchase pending...";
    hoursLabel.text = @"";
}

- (void)speedBoostChargingWithHoursEarned:(NSUInteger)hoursEarned andProgressToNextHourEarned:(float)progress {
    if (hoursEarned >= 1) {
        title.text = [@"Speed Boost Charged" stringByAppendingFormat:@" %.0f%%", progress * 100];
    } else {
        title.text = [@"Speed Boost Charging" stringByAppendingFormat:@" %.0f%%", progress * 100];
    }
    [self setHoursLabelToHours:hoursEarned];
}

- (NSTimeInterval)timeToNextHourExpired:(NSTimeInterval)seconds {
    NSTimeInterval secondsRemaining = seconds;
#if DEBUG
    NSInteger hoursRemaining = secondsRemaining / (10);
    NSTimeInterval secondsToNextHourExpired = secondsRemaining - (hoursRemaining * 10);
#else
    NSInteger hoursRemaining = secondsRemaining / (60*60);
    NSTimeInterval secondsToNextHourExpired = secondsRemaining - (hoursRemaining * 60);
#endif
    return secondsToNextHourExpired;
}

- (void)activeSpeedBoostExpiringIn:(NSTimeInterval)seconds {
    if (seconds > 0) {
#if DEBUG
        NSUInteger hours = seconds/10;
#else
        NSUInteger hours = seconds/(60*60);
#endif
        title.text = @"Speed Boosting!";
        [self setHoursLabelToHours:hours];
        dispatch_async(dispatch_get_main_queue(), ^{
            countdownToNextHourExpired = [NSTimer scheduledTimerWithTimeInterval:[self timeToNextHourExpired:seconds] repeats:NO block:^(NSTimer * _Nonnull timer) {
                [self activeSpeedBoostExpiringIn:self.model.activeSpeedBoostPurchase.expiryDate.timeIntervalSinceNow];
            }];
        });
    } else {
        title.text = @"Speed Boost expired.";
        [self setHoursLabelToHours:0];
    }
}

- (void)setHoursLabelToHours:(NSUInteger)hours {
    hoursLabel.text = [NSString stringWithFormat:@"%luh", (unsigned long)hours];
}

# pragma mark - PsiCashClientModelReceiver protocol

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    self.model = clientModel;

    if (countdownToNextHourExpired != nil) {
        NSLog(@"ExpiringPurchases: invalidating timer");
        [countdownToNextHourExpired invalidate];
    }

    if ([self.model hasAuthPackage]) {
        if ([self.model hasActiveSpeedBoostPurchase]) {
            [self activeSpeedBoostExpiringIn:self.model.activeSpeedBoostPurchase.expiryDate.timeIntervalSinceNow];
        } else if ([self.model hasPendingPurchase]){
            [self inPurchasePendingState];
        } else {
            if ([self.model.authPackage hasSpenderToken]) {
                [self speedBoostChargingWithHoursEarned:[self.model hoursEarned] andProgressToNextHourEarned:[self.model progressToNextHourEarned]];
            } else {
                assert(false); // TODO: user has no spender token
            }
        }
    } else {
        [self inRetrievingAuthPackageState];
    }
}

@end

