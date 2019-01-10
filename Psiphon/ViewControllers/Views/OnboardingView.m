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

#import "OnboardingView.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"
#import "Logging.h"

@implementation OnboardingView {
    // Set in init.
    UIImage *image;
    NSString *title;
    NSString *body;
    UIView *_Nullable accessoryView;

    // Internal views.
    UIImageView *imageView;
    UILabel *titleLabel;
    UILabel *bodyLabel;

    NSLayoutConstraint *accessoryViewBottomConstraint;
    NSLayoutConstraint *accessoryViewTopConstraint;
}

- (instancetype)initWithImage:(UIImage *)image
                    withTitle:(NSString *)title
                     withBody:(NSString *)body
            withAccessoryView:(UIView *_Nullable)accessoryView {

    self = [super init];
    if (self) {
        _anchorAccessoryViewToBottom = FALSE;
        self->image = image;
        self->title = title;
        self->body = body;
        self->accessoryView = accessoryView;
        [self customSetup];
    }
    return self;
}

- (void)setAnchorAccessoryViewToBottom:(BOOL)anchorAccessoryViewToBottom {
    _anchorAccessoryViewToBottom = anchorAccessoryViewToBottom;
    accessoryViewBottomConstraint.active = _anchorAccessoryViewToBottom;
    accessoryViewTopConstraint.active = !_anchorAccessoryViewToBottom;
}

- (void)setupViews {
    imageView = [[UIImageView alloc] init];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.clipsToBounds = TRUE;

    titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.backgroundColor = UIColor.clearColor;
    titleLabel.adjustsFontSizeToFitWidth = TRUE;
    titleLabel.font = [UIFont avenirNextDemiBold:22.f];
    titleLabel.textColor = UIColor.lightishBlue;

    bodyLabel = [[UILabel alloc] init];
    bodyLabel.text = body;
    bodyLabel.backgroundColor = UIColor.clearColor;
    bodyLabel.font = [UIFont avenirNextMedium:16.f];
    bodyLabel.textColor = UIColor.greyishBrown;
    bodyLabel.numberOfLines = 0;
    bodyLabel.lineBreakMode = NSLineBreakByClipping;
    bodyLabel.textAlignment = NSTextAlignmentCenter;
    bodyLabel.adjustsFontSizeToFitWidth = TRUE;
    bodyLabel.minimumScaleFactor = 0.7;
}

- (void)addSubviews {
    [self addSubview:imageView];
    [self addSubview:titleLabel];
    [self addSubview:bodyLabel];
    if (accessoryView) {
        [self addSubview:accessoryView];
    }
}

- (void)setupSubviewsLayoutConstraints {

    CGFloat invAspectRatio = 0.8f * (imageView.image.size.height / imageView.image.size.width);
    imageView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
      [imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
      [imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
      [imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [imageView.heightAnchor constraintEqualToAnchor:imageView.widthAnchor
                                           multiplier:invAspectRatio]
    ]];

    titleLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
    [titleLabel setContentHuggingPriority:1000
                                  forAxis:UILayoutConstraintAxisVertical];
    [NSLayoutConstraint activateConstraints:@[
      [titleLabel.topAnchor constraintEqualToAnchor:imageView.bottomAnchor constant:10.f],
      [titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor]
    ]];

    bodyLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
      [bodyLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:15.f],
      [bodyLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

      [bodyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor
                                                           constant:20.f],

      [bodyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                         constant:-20.f]
    ]];

    if (accessoryView) {
        accessoryView.translatesAutoresizingMaskIntoConstraints = FALSE;

        [NSLayoutConstraint activateConstraints:@[
          [accessoryView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
          [accessoryView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20.f],
          [accessoryView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20.f],
        ]];

        accessoryViewBottomConstraint = [accessoryView.bottomAnchor
          constraintEqualToAnchor:self.bottomAnchor];

        accessoryViewTopConstraint = [accessoryView.topAnchor
          constraintEqualToAnchor:bodyLabel.bottomAnchor
                         constant:20.f];

        accessoryViewBottomConstraint.active = _anchorAccessoryViewToBottom;
        accessoryViewTopConstraint.active = !_anchorAccessoryViewToBottom;
    }
}

@end
