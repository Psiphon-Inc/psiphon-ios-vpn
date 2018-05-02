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

#import "PsiCashSpeedBoostTableViewCell.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostMeterView.h"

@interface PsiCashSpeedBoostTableViewCell ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

#pragma mark -

@implementation PsiCashSpeedBoostTableViewCell {
    PsiCashSpeedBoostMeterView *speedBoostMeter;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        speedBoostMeter = [[PsiCashSpeedBoostMeterView alloc] init];
        [self.contentView addSubview:speedBoostMeter];

        speedBoostMeter.translatesAutoresizingMaskIntoConstraints = NO;
        [speedBoostMeter.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor].active = YES;
        [speedBoostMeter.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor].active = YES;
        [speedBoostMeter.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor multiplier:0.75].active = YES;
        [speedBoostMeter.heightAnchor constraintEqualToAnchor:self.contentView.heightAnchor multiplier:0.5f].active = YES;
    }

    return self;
}

#pragma mark - PsiCashClientModelReceiver protocol

- (void)bindWithModel:(PsiCashClientModel*)clientModel {
    self.model = clientModel;
    [speedBoostMeter bindWithModel:self.model];
}

@end

