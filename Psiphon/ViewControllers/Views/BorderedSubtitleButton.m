/*
* Copyright (c) 2019, Psiphon Inc.
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

#import "BorderedSubtitleButton.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"

#define topBottomPadding 13.0

@implementation BorderedSubtitleButton {
    NSArray<NSLayoutConstraint *> *subtitleConstraints;
}

@synthesize subtitleLabel = _subtitleLabel;

const CGFloat sutitleFontRatio = 0.92;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _subtitleLabel = [[UILabel alloc] init];
    }
    return self;
}

- (void)setFontSize:(CGFloat)fontSize {
    [super setFontSize:fontSize];
    _subtitleLabel.font = [UIFont avenirNextDemiBold:sutitleFontRatio * fontSize];
}

- (void)autoLayoutSetupViews {
    [super autoLayoutSetupViews];

    self.backgroundColor = UIColor.black19Color;
    self.layer.cornerRadius = 8.0;
    self.layer.borderColor = UIColor.lightishBlue.CGColor;
    self.layer.borderWidth = 2.0;

    [self setLabelProperties:_subtitleLabel withFontSize:sutitleFontRatio * self.fontSize];

    // We allow subtitle to be multiline.
    _subtitleLabel.numberOfLines = 0;
    _subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;

}

- (void)autoLayoutAddSubviews {
    [super autoLayoutAddSubviews];
    [self addSubview: self.subtitleLabel];
}

// Overriding parent layout constraints.
- (void)autoLayoutSetupSubviewsLayoutConstraints {

    self.titleLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = FALSE;

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:topBottomPadding],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4.0],
    ]];

    subtitleConstraints = @[
        [_subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4.0],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0],
        [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-topBottomPadding],
    ];

    [NSLayoutConstraint activateConstraints: subtitleConstraints];
}

#pragma mark -

- (void)removeSubtitleLabel {
    _subtitleLabel.hidden = TRUE;
    [NSLayoutConstraint deactivateConstraints:subtitleConstraints];
    [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-topBottomPadding].active = TRUE;
}

@end
