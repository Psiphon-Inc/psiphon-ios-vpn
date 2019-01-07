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

#import <ImageIO/ImageIO.h>
#import "SkyButton.h"
#import "UIFont+Additions.h"
#import "Logging.h"

@implementation SkyButton {
    NSString *normalTitle;
    NSString *disabledTitle;
}

@synthesize titleLabel = _titleLabel;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleLabel = [[UILabel alloc] init];
        _fontSize = 15.f;
        _shadow = FALSE;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.shadow) {
        UIBezierPath *shadowPath = [UIBezierPath bezierPathWithRect:self.bounds];
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOffset = CGSizeMake(0.f, 1.5f);
        self.layer.shadowOpacity = 0.15f;
        self.layer.shadowPath = shadowPath.CGPath;
        self.layer.shadowRadius = 3.f;
    } else {
        self.layer.shadowOpacity = 0.f;
    }
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    _titleLabel.text = self.currentTitle;
}

- (void)setTitle:(NSString *)title {
    normalTitle = title;
    disabledTitle = title;
    _titleLabel.text = title;
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

#pragma mark - AutoLayoutProtocol

- (instancetype)initForAutoLayout {
    self = [self initWithFrame:CGRectZero];
    if (self) {
        [self autoLayoutInit];
    }
    return self;
}

- (void)autoLayoutInit {
    self.translatesAutoresizingMaskIntoConstraints = FALSE;
    [self autoLayoutSetupViews];
    [self autoLayoutAddSubviews];
    [self autoLayoutSetupSubviewsLayoutConstraints];
}

- (void)autoLayoutSetupViews {
    CGFloat cornerRadius = 8.f;

    self.layer.masksToBounds = FALSE;
    self.layer.cornerRadius = cornerRadius;

    _titleLabel.backgroundColor = UIColor.clearColor;

    _titleLabel.adjustsFontSizeToFitWidth = TRUE;
    _titleLabel.minimumScaleFactor = 0.8;
    _titleLabel.font = [UIFont avenirNextDemiBold:self.fontSize];

    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.userInteractionEnabled = FALSE;
    _titleLabel.clipsToBounds = TRUE;
    _titleLabel.backgroundColor = UIColor.clearColor;
}

- (void)autoLayoutAddSubviews {
    [self addSubview:self.titleLabel];
}

- (void)autoLayoutSetupSubviewsLayoutConstraints {
    _titleLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
    [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = TRUE;

    [_titleLabel.topAnchor
      constraintEqualToAnchor:self.topAnchor
                     constant:self.fontSize].active = TRUE;

    [_titleLabel.bottomAnchor
      constraintEqualToAnchor:self.bottomAnchor
                       constant:-self.fontSize].active = TRUE;

    UIControlContentHorizontalAlignment alignment = self.contentHorizontalAlignment;
    if (alignment == UIControlContentHorizontalAlignmentCenter) {
        [_titleLabel.widthAnchor
          constraintEqualToAnchor:self.widthAnchor
                         constant:-(self.fontSize + 5.f)].active = TRUE;

        [_titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = TRUE;

    } else if (alignment == UIControlContentHorizontalAlignmentLeft) {
        // We take left to mean leading.
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                 constant:self.fontSize + 5.f].active = TRUE;
    }
}

#pragma mark - Touch animation

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [UIView animateWithDuration:0.1
                     animations:^{
                        self.transform = CGAffineTransformMakeScale(0.98f, 0.98f);
                        self.alpha = 0.8;
                     }];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [UIView animateWithDuration:0.1
                     animations:^{
                         self.transform = CGAffineTransformMakeScale(1.f, 1.f);
                         self.alpha = 1.0;
                     }];
}

@end
