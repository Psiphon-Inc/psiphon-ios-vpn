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

#import "OnboardingScrollableView.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"

@implementation OnboardingScrollableView {
    // Set in init.
    UIImage *image;
    NSString *title;
    NSString *body;
    UIView *_Nullable accessoryView;

    // Internal views.
    UIScrollView *scrollView;
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
        self->image = image;
        self->title = title;
        self->body = body;
        self->accessoryView = accessoryView;
        [self customSetup];
    }
    return self;
}

- (void)setupViews {
    scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];

    imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.clipsToBounds = TRUE;

    titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = title;
    titleLabel.backgroundColor = UIColor.clearColor;
    titleLabel.adjustsFontSizeToFitWidth = TRUE;
    titleLabel.font = [UIFont avenirNextDemiBold:22.f];
    titleLabel.textColor = UIColor.lightishBlue;

    bodyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    bodyLabel.numberOfLines = 0;

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc]
      initWithData:[body dataUsingEncoding:NSUnicodeStringEncoding]
           options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType}
documentAttributes:nil
             error:nil];

    // Enumerate font attributes and updates to desired font.
    [attributedString enumerateAttribute:NSFontAttributeName
                                 inRange:NSMakeRange(0, [attributedString length])
                                 options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired
                              usingBlock:^(UIFont *currentFont, NSRange range, BOOL *stop) {

                                  NSRange boldRange = [currentFont.fontName rangeOfString:@"bold"
                                                                                  options:NSCaseInsensitiveSearch];
                                  UIFont *newFont;
                                  if (boldRange.location != NSNotFound) {
                                      newFont = [UIFont avenirNextDemiBold:currentFont.pointSize];
                                  } else {
                                      newFont = [UIFont avenirNextMedium:currentFont.pointSize];
                                  }

                                  [attributedString addAttribute:NSFontAttributeName value:newFont range:range];
                              }];

    bodyLabel.attributedText = attributedString;
}

- (void)addSubviews {
    [self addSubview:scrollView];
    [scrollView addSubview:imageView];
    [scrollView addSubview:titleLabel];
    [scrollView addSubview:bodyLabel];

    if (accessoryView) {
        [self addSubview:accessoryView];
    }
}

- (void)setupSubviewsLayoutConstraints {

    // scrollView
    scrollView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = TRUE;
    [scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = TRUE;
    [scrollView.topAnchor constraintEqualToAnchor:self.topAnchor].active = TRUE;
    if (accessoryView) {
        [scrollView.bottomAnchor constraintEqualToAnchor:accessoryView.topAnchor].active = TRUE;
    } else {
        [scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = TRUE;
    }

    // imageView
    CGFloat invAspectRatio = 0.8f * (imageView.image.size.height / imageView.image.size.width);
    imageView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [imageView.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:25.f].active = TRUE;
    [imageView.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor].active = TRUE;
    [imageView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor].active = TRUE;
    [imageView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor].active = TRUE;
    [imageView.heightAnchor constraintEqualToAnchor:imageView.widthAnchor
                                         multiplier:invAspectRatio].active = TRUE;

    // titleLabel
    titleLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
    [titleLabel.topAnchor constraintEqualToAnchor:imageView.bottomAnchor constant:10.f]
      .active = TRUE;
    [titleLabel.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor].active = TRUE;

    // bodyLabel
    bodyLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
    [bodyLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                        constant:15.f].active = TRUE;

    [bodyLabel.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor
                                           constant:15.f].active = TRUE;

    [bodyLabel.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor].active = TRUE;

    [bodyLabel.leadingAnchor
      constraintGreaterThanOrEqualToAnchor:scrollView.leadingAnchor].active = TRUE;

    [bodyLabel.trailingAnchor
      constraintLessThanOrEqualToAnchor:scrollView.trailingAnchor].active = TRUE;

    // accessoryView
    if (accessoryView) {
        accessoryView.translatesAutoresizingMaskIntoConstraints = FALSE;

        [accessoryView.centerXAnchor
          constraintEqualToAnchor:self.centerXAnchor].active = TRUE;

        [accessoryView.leadingAnchor
          constraintEqualToAnchor:self.leadingAnchor].active = TRUE;

        [accessoryView.trailingAnchor
          constraintEqualToAnchor:self.trailingAnchor].active = TRUE;

        [accessoryView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = TRUE;
    }
}

@end
