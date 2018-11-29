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
    [self setNeedsUpdateConstraints];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.anchorAccessoryViewToBottom) {
        [accessoryView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = TRUE;
    } else {
        [accessoryView.topAnchor
          constraintEqualToAnchor:bodyLabel.bottomAnchor
                         constant:20.f].active = TRUE;
    }
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
    {
        CGFloat invAspectRatio = 0.8f * (imageView.image.size.height / imageView.image.size.width);
        imageView.translatesAutoresizingMaskIntoConstraints = FALSE;
        [imageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:25.f].active = TRUE;
        [imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = TRUE;
        [imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = TRUE;
        [imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = TRUE;
        [imageView.heightAnchor constraintEqualToAnchor:imageView.widthAnchor
                                             multiplier:invAspectRatio].active = TRUE;
    }

    {
        [titleLabel setContentHuggingPriority:1000
                                      forAxis:UILayoutConstraintAxisVertical];

        titleLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
        [titleLabel.topAnchor constraintEqualToAnchor:imageView.bottomAnchor constant:10.f]
          .active = TRUE;
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = TRUE;
    }

    {
        bodyLabel.translatesAutoresizingMaskIntoConstraints = FALSE;

        [bodyLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                            constant:15.f].active = TRUE;

        [bodyLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = TRUE;

        [bodyLabel.leadingAnchor
          constraintGreaterThanOrEqualToAnchor:self.leadingAnchor].active = TRUE;

        [bodyLabel.trailingAnchor
          constraintLessThanOrEqualToAnchor:self.trailingAnchor].active = TRUE;
    }

    if (accessoryView) {
        accessoryView.translatesAutoresizingMaskIntoConstraints = FALSE;

        [accessoryView.centerXAnchor
          constraintEqualToAnchor:self.centerXAnchor].active = TRUE;

        [accessoryView.leadingAnchor
          constraintEqualToAnchor:self.leadingAnchor].active = TRUE;

        [accessoryView.trailingAnchor
          constraintEqualToAnchor:self.trailingAnchor].active = TRUE;
    }
}

@end
