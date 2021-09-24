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
#import "Psiphon-Swift.h"

@implementation OnboardingScrollableView {
    // Set in init.
    UIImage *image;
    NSString *title;
    NSString *htmlBody;
    UIView *_Nullable accessoryView;

    // Internal views.
    FoldingScrollView *scrollView;
    UIImageView *imageView;
    UILabel *titleLabel;
    UITextView *bodyTextView;
}

- (instancetype)initWithImage:(UIImage *)image
                    withTitle:(NSString *)title
                     withHTMLBody:(NSString *)htmlBody
            withAccessoryView:(UIView *_Nullable)accessoryView {

    self = [super init];
    if (self) {
        self->image = image;
        self->title = title;
        self->htmlBody = htmlBody;
        self->accessoryView = accessoryView;
        [self customSetup];
    }
    return self;
}

- (void)setupViews {
    scrollView = [[FoldingScrollView alloc] initWithFrame:CGRectZero];
    scrollView.delegate = self;

    imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.clipsToBounds = TRUE;

    titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = title;
    titleLabel.backgroundColor = UIColor.clearColor;
    titleLabel.adjustsFontSizeToFitWidth = TRUE;
    titleLabel.font = [UIFont avenirNextDemiBold:22.f];
    titleLabel.textColor = UIColor.whiteColor;

    bodyTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    bodyTextView.scrollEnabled = FALSE; // UITextView is already nested in a UIScrollView.
    bodyTextView.editable = FALSE;
    bodyTextView.backgroundColor = UIColor.clearColor;

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc]
            initWithData:[htmlBody dataUsingEncoding:NSUnicodeStringEncoding]
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

          // Set color
          [attributedString addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor range:range];
      }];
    
    // Forces attributedString text alignment for RTL languages.
    if (UIApplication.sharedApplication.userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) {
        
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        paragraphStyle.alignment = NSTextAlignmentRight;
        
        [attributedString addAttribute:NSParagraphStyleAttributeName
                                 value:paragraphStyle
                                 range:NSMakeRange(0, attributedString.length)];
    }

    bodyTextView.attributedText = attributedString;
    
}

- (void)addSubviews {
    [self addSubview:scrollView];
    [scrollView addSubview:imageView];
    [scrollView addSubview:titleLabel];
    [scrollView addSubview:bodyTextView];

    if (accessoryView) {
        [self addSubview:accessoryView];
    }
}

- (void)setupSubviewsLayoutConstraints {

    // scrollView
    scrollView.translatesAutoresizingMaskIntoConstraints = FALSE;


    NSLayoutConstraint *scrollViewBottomAnchor;
    if (accessoryView) {
        scrollViewBottomAnchor = [scrollView.bottomAnchor
          constraintEqualToAnchor:accessoryView.topAnchor];
    } else {
        scrollViewBottomAnchor = [scrollView.bottomAnchor
          constraintEqualToAnchor:self.bottomAnchor];
    }

    [NSLayoutConstraint activateConstraints:@[
      [scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
      scrollViewBottomAnchor
    ]];


    // imageView
    CGFloat invAspectRatio = 0.8f * (imageView.image.size.height / imageView.image.size.width);
    imageView.translatesAutoresizingMaskIntoConstraints = FALSE;

    [NSLayoutConstraint activateConstraints:@[
      [imageView.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:25.f],
      [imageView.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor],
      [imageView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
      [imageView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
      [imageView.heightAnchor constraintEqualToAnchor:imageView.widthAnchor
                                           multiplier:invAspectRatio]
    ]];

    // titleLabel
    titleLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
      [titleLabel.topAnchor constraintEqualToAnchor:imageView.bottomAnchor constant:10.f],
      [titleLabel.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor]
    ]];

    // bodyTextView
    bodyTextView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
      [bodyTextView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:15.f],
      [bodyTextView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:15.f],
      [bodyTextView.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor],
      [bodyTextView.leadingAnchor constraintGreaterThanOrEqualToAnchor:scrollView.leadingAnchor
                                                           constant:20.f],
      [bodyTextView.trailingAnchor constraintLessThanOrEqualToAnchor:scrollView.trailingAnchor
                                                         constant:-20.f]
    ]];

    // accessoryView
    if (accessoryView) {
        accessoryView.translatesAutoresizingMaskIntoConstraints = FALSE;

        [NSLayoutConstraint activateConstraints:@[
          [accessoryView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
          [accessoryView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
          [accessoryView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20.f],
          [accessoryView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20.f]
        ]];
    }
}

@end
