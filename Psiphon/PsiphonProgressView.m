/*
 * Copyright (c) 2017, Psiphon Inc. Created by Draven Johnson on 2017-08-30.
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

#import "LoadingCircleLayer.h"
#import "PsiphonProgressView.h"
#import "PureLayout.h"

#define kLogoRatioOfMinDimension 0.7f

@implementation PsiphonProgressView {
    UIImage *logo;
    UIImageView *logoView;
    NSLayoutConstraint *logoViewWidth;
    NSLayoutConstraint *logoViewHeight;

    LoadingCircleLayer *loadingCircle;

}

-(id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setBackgroundColor:[UIColor clearColor]];
        [self setupViews];
        [self setupLayoutConstraints];
    }

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [loadingCircle setFrame:self.bounds];

    // Only trigger constraint updates if bounds have changed
    CGSize size = [self size];
    if (logoViewWidth.constant != size.width || logoViewHeight.constant != size.height) {
        [self setNeedsUpdateConstraints];
    }
}

- (void)setProgress:(CGFloat)progress {
    if (loadingCircle) {
        loadingCircle.progress = progress;
    }
}

- (void)updateConstraints {
    CGSize size = [self size];
    logoViewWidth.constant = size.width;
    logoViewHeight.constant = size.height;
    [super updateConstraints];
}

#pragma mark - helpers

- (void)setupViews {
    logo = [UIImage imageNamed:@"LaunchScreen"];
    logoView = [[UIImageView alloc] initWithImage:logo];
    logoView.contentMode = UIViewContentModeScaleAspectFill;
    [self addSubview:logoView];

    loadingCircle = [[LoadingCircleLayer alloc] init];
    loadingCircle.lineWidth = 5.f;
    loadingCircle.circleRadiusRatio = .8f;
    loadingCircle.updateDuration = 1.f;
    [self.layer addSublayer:loadingCircle];
}

- (void)setupLayoutConstraints {
    logoView.translatesAutoresizingMaskIntoConstraints = NO;

    CGSize size = [self size];
    logoViewWidth = [logoView.widthAnchor constraintEqualToConstant:size.width];
    logoViewHeight = [logoView.heightAnchor constraintEqualToConstant:size.height];
    logoViewWidth.active = YES;
    logoViewHeight.active = YES;

    [logoView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [logoView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
}

- (CGSize)size {
    CGFloat len = kLogoRatioOfMinDimension * [self minDimensionLength];
    return CGSizeMake(len, len);
}

- (CGFloat)minDimensionLength {
    return MIN(self.frame.size.width, self.frame.size.height);
}

@end
