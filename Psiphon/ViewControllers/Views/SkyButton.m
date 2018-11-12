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

#import "SkyButton.h"
#import "UIFont+Additions.h"

@implementation SkyButton {
    UILabel *titleLabel;
    NSString *normalTitle;
    NSString *disabledTitle;
}

- (void)setTitle:(NSString *)title {
    normalTitle = title;
    disabledTitle = title;
}

- (void)setTitle:(NSString *)title forState:(UIControlState)controlState {
    if (controlState == UIControlStateNormal) {
        normalTitle = title;
    } else if (controlState == UIControlStateDisabled) {
        disabledTitle = title;
    }
}

- (NSString *)currentTitle {
    if (self.enabled) {
        return normalTitle;
    } else {
        return disabledTitle;
    }
}

#pragma mark - Getter

- (UILabel *)titleLabel {
    return titleLabel;
}

#pragma mark - AutoLayoutProtocol

- (instancetype)initForAutoLayout {
    self = [self initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = FALSE;
        [self autoLayoutSetupViews];
        [self autoLayoutAddSubviews];
        [self autoLayoutSetupSubviewsLayoutConstraints];
    }
    return self;
}

- (void)autoLayoutSetupViews {
    self.clipsToBounds = YES;

    CGFloat cornerRadius = 8.f;

    titleLabel = [[UILabel alloc] init];
    titleLabel.backgroundColor = [UIColor clearColor];

    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.8;
    titleLabel.font = [UIFont avenirNextDemiBold:16.f];

    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.userInteractionEnabled = NO;
    titleLabel.layer.cornerRadius = cornerRadius;
    titleLabel.clipsToBounds = YES;
    titleLabel.backgroundColor = [UIColor clearColor];
}

- (void)autoLayoutAddSubviews {
    [self addSubview:self.titleLabel];
}

- (void)autoLayoutSetupSubviewsLayoutConstraints {
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [titleLabel.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-20.f].active = TRUE;
}

@end
