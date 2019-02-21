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

#import "VPNStartAndStopButton.h"
#import "SVIndefiniteAnimatedView.h"

@implementation VPNStartAndStopButton {
    UIImageView *centerImageView;
    SVIndefiniteAnimatedView *connectingSpinner;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        
        self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
        self.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;

        // Shadow and Radius
//        self.layer.shadowOffset = CGSizeMake(0, 2.0f);
//        self.layer.shadowOpacity = 0.18f;
//        self.layer.shadowRadius = 0.0f;
//        self.layer.masksToBounds = NO;

        centerImageView = [[UIImageView alloc] init];
        [self addSubview: centerImageView];
        centerImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [centerImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
        [centerImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
        [centerImageView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:.25f].active = YES;
        [centerImageView.heightAnchor constraintEqualToAnchor:centerImageView.widthAnchor].active = YES;
        
        connectingSpinner = [[SVIndefiniteAnimatedView alloc] initWithFrame:CGRectZero];
        
        connectingSpinner.strokeColor = [UIColor colorWithRed:0.50 green:0.74 blue:1.00 alpha:1.0];
        connectingSpinner.strokeThickness = 5.f;
        
        connectingSpinner.userInteractionEnabled = NO;
    }

    return self;
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    connectingSpinner.bounds = bounds;
    connectingSpinner.radius = bounds.size.width / 2 - 2.5;
}

- (void)addConnectingSpinner {
    [self addSubview:connectingSpinner];
    connectingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [connectingSpinner.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    [connectingSpinner.heightAnchor constraintEqualToAnchor:connectingSpinner.widthAnchor].active = YES;
    [connectingSpinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [connectingSpinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
}

- (void)removeConnectingSpinner {
    [connectingSpinner removeFromSuperview];
}

- (void)setConnecting {
    UIImage *connectingButtonImage = [UIImage imageNamed:@"StartButton"];
    [self setImage:connectingButtonImage forState:UIControlStateNormal];

    centerImageView.image = [UIImage imageNamed:@"ConnectingButtonCentre"];

    [self addConnectingSpinner];
}

- (void)setConnected {
    [self removeConnectingSpinner];
    
    UIImage *stopButtonImage = [UIImage imageNamed:@"StopButton"];
    [self setImage:stopButtonImage forState:UIControlStateNormal];

    centerImageView.image = [UIImage imageNamed:@"StopButtonCentre"];
}

- (void)setDisconnected {
    [self removeConnectingSpinner];
    
    UIImage *startButtonImage = [UIImage imageNamed:@"StartButton"];
    [self setImage:startButtonImage forState:UIControlStateNormal];

    centerImageView.image = [UIImage imageNamed:@"StartButtonCentre"];
}

@end
