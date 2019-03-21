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

#import "ActivityIndicatorRoyalSkyButton.h"


@implementation ActivityIndicatorRoyalSkyButton {
    UIActivityIndicatorView *activityIndicator;

    AIRSBState buttonState;
    NSMutableDictionary<NSNumber *, NSString *> *titles;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        buttonState = AIRSBStateNormal;
        titles = [NSMutableDictionary dictionaryWithCapacity:ENUM_COUNT_AIRSBState];
        activityIndicator = [[UIActivityIndicatorView alloc]
          initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    }
    return self;
}

- (void)setTitle:(NSString *)title forButtonState:(AIRSBState)s {
    titles[@(s)] = title;

    // Update title of current active state title changes.
    if (buttonState == s) {
        [self updateTitle];
    }
}

- (void)setState:(AIRSBState)s {
    if (buttonState == s) {
        return;
    }

    buttonState = s;
    switch (s) {
        case AIRSBStateNormal: {
            self.userInteractionEnabled = TRUE;
            self.enabled = TRUE;
            [self setBackgroundGradient:TRUE];
            [activityIndicator stopAnimating];
            break;
        }
        case AIRSBStateDisabled: {
            self.userInteractionEnabled = FALSE;
            self.enabled = FALSE;
            [self setBackgroundGradient:FALSE];
            [activityIndicator stopAnimating];
            break;
        }
        case AIRSBStateAnimating: {
            self.userInteractionEnabled = FALSE;
            self.enabled = FALSE;
            [self setBackgroundGradient:FALSE];
            [activityIndicator startAnimating];
            break;
        }
        case AIRSBStateRetry: {
            self.userInteractionEnabled = TRUE;
            self.enabled = TRUE;
            [self setBackgroundGradient:TRUE];
            [activityIndicator stopAnimating];
            break;
        }
    }

    [self updateTitle];
}

#pragma mark -

- (NSString *)currentTitle {
    return titles[@(buttonState)];
}

#pragma mark - AutoLayoutProtocol init

- (void)autoLayoutSetupViews {
    [super autoLayoutSetupViews];

    self.userInteractionEnabled = TRUE;
    [self setBackgroundGradient:TRUE];
    [activityIndicator stopAnimating];
}

- (void)autoLayoutAddSubviews {
    [super autoLayoutAddSubviews];
    [self addSubview:activityIndicator];
}

- (void)autoLayoutSetupSubviewsLayoutConstraints {
    [super autoLayoutSetupSubviewsLayoutConstraints];

    activityIndicator.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
      [activityIndicator.topAnchor constraintLessThanOrEqualToAnchor:self.topAnchor],
      [activityIndicator.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.bottomAnchor],
      [activityIndicator.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [activityIndicator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                       constant:-10.f]
    ]];
}


@end
