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

#import "RegionSelectionButton.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"
#import "UIImage+CountryFlag.h"
#import "ImageUtils.h"

@implementation RegionSelectionButton {
    UIImageView *flagImageView;
    UILabel *regionNameLabel;
    UIImageView *rightArrow;
    BOOL isRTL;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {

        isRTL = ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);

        [self setBackgroundColor:[UIColor clearColor]];
        self.layer.cornerRadius = 8;
        self.layer.borderColor = UIColor.lightishBlueTwo.CGColor;
        self.layer.borderWidth = 2.f;

        flagImageView = [[UIImageView alloc] init];

        regionNameLabel = [[UILabel alloc] init];
        regionNameLabel.adjustsFontSizeToFitWidth = YES;
        regionNameLabel.font = [UIFont avenirNextMedium:16.f];
        regionNameLabel.textColor = UIColor.whiteColor;
        if (isRTL) {
            regionNameLabel.textAlignment = NSTextAlignmentRight;
        }

        rightArrow = [[UIImageView alloc] init];

        [self addViews];
        [self setupAutoLayoutConstraints];
        
    }

    return self;
}

- (void)addViews {
    [self addSubview:flagImageView];
    [self addSubview:regionNameLabel];
    [self addSubview:rightArrow];
}

- (void)setupAutoLayoutConstraints {
    flagImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [flagImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14.f].active = YES;
    [flagImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [flagImageView.widthAnchor constraintEqualToConstant:41.f].active = YES;
    [flagImageView.heightAnchor constraintEqualToConstant:29.f].active = YES;
    [flagImageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:14.0].active = YES;
    [flagImageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14.0].active = YES;

    regionNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [regionNameLabel.leadingAnchor constraintEqualToAnchor:flagImageView.trailingAnchor constant:14.f].active = YES;
    [regionNameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [regionNameLabel.trailingAnchor constraintEqualToAnchor:rightArrow.leadingAnchor constant:-5.f].active = YES;

    UIImage *rightArrowImage = [UIImage imageNamed:@"ChevronWhite"];
    rightArrow.image = rightArrowImage;
    rightArrow.translatesAutoresizingMaskIntoConstraints = NO;
    [rightArrow.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20.f].active = YES;
    [rightArrow.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [rightArrow.widthAnchor constraintEqualToConstant:rightArrowImage.size.width].active = YES;
    [rightArrow.heightAnchor constraintEqualToConstant:rightArrowImage.size.height].active = YES;

    if (isRTL) {
        rightArrow.transform = CGAffineTransformMakeRotation((CGFloat)M_PI);
    }
}

- (void)bind:(Region *)selectedRegion {
    flagImageView.image = [ImageUtils regionFlagForResourceId:selectedRegion.flagResourceId];

    NSString *regionText = [[RegionAdapter sharedInstance] getLocalizedRegionTitle:selectedRegion.code];
    regionNameLabel.attributedText = [self styleRegionLabelText:regionText];
}

- (NSAttributedString*)styleRegionLabelText:(NSString*)s {
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc] initWithString:s];
    [mutableStr addAttribute:NSKernAttributeName
                       value:@-0.3
                       range:NSMakeRange(0, mutableStr.length)];
    return mutableStr;
}

@end
