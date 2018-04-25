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

#import "PsiCashBalanceTableViewCell.h"
#import "PsiCashBalanceView.h"

@interface PsiCashBalanceTableViewCell ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

#pragma mark -

@implementation PsiCashBalanceTableViewCell {
    PsiCashBalanceView *balanceView;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        balanceView = [[PsiCashBalanceView alloc] init];
        [self.contentView addSubview:balanceView];

        balanceView.translatesAutoresizingMaskIntoConstraints = NO;
        [balanceView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor].active = YES;
        [balanceView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor].active = YES;
        [balanceView.widthAnchor constraintEqualToConstant:200.f].active = YES;
        [balanceView.heightAnchor constraintEqualToConstant:45.f].active = YES;
    }

    return self;
}

#pragma mark - PsiCashClientModelReceiver protocol

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    self.model = clientModel;
    [balanceView bindWithModel:clientModel];
}

@end

