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
#import "UIView+AutoLayoutViewGroup.h"

@implementation PsiphonProgressView {
    UIImage *logo;
    UIImageView *logoView;
    LoadingCircleLayer *loadingCircle;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [loadingCircle setFrame:self.bounds];
}

- (void)setProgress:(CGFloat)progress {
    if (loadingCircle) {
        loadingCircle.progress = progress;
    }
}

#pragma mark - helpers

- (void)setupViews {
    [self setBackgroundColor:[UIColor clearColor]];

    logo = [UIImage imageNamed:@"LaunchScreen"];
    logoView = [[UIImageView alloc] initWithImage:logo];
    logoView.contentMode = UIViewContentModeScaleAspectFill;

    loadingCircle = [[LoadingCircleLayer alloc] init];
    loadingCircle.lineWidth = 5.f;
    loadingCircle.circleRadiusRatio = .8f;
    loadingCircle.updateDuration = 1.f;
    [self.layer addSublayer:loadingCircle];
}

- (void)addSubviews {
    [self addSubview:logoView];
}

- (void)setupSubviewsLayoutConstraints {
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    [logoView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [logoView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
}

@end
