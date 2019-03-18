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
    NSString *titleIndicatorAnimating;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        activityIndicator = [[UIActivityIndicatorView alloc]
          initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    }
    return self;
}

- (void)setTitleForIndicatorAnimating:(NSString *)title {
    titleIndicatorAnimating = title;
}

- (void)startAnimating {
    if (!activityIndicator.animating) {
        [activityIndicator startAnimating];
        [self updateTitle];
    }
}

- (void)stopAnimating {
    if (activityIndicator.animating) {
        [activityIndicator stopAnimating];
        [self updateTitle];
    }
}

#pragma mark -

- (NSString *)currentTitle {
    if (activityIndicator.animating) {
        return titleIndicatorAnimating;
    } else {
        return [super currentTitle];
    }
}

#pragma mark - AutoLayoutProtocol init

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
