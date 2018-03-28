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

#import "PsiCashBalanceView.h"
#import "PsiCashClient.h"
#import "ReactiveObjC.h"

@interface PsiCashBalanceView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

#pragma mark -

@implementation PsiCashBalanceView {
    UIImageView *animatingCoin;
    UILabel *balance;
    UILabel *plusMinusIndicator;
}

-(id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setupViews];
        [self addViews];
        [self setupLayoutConstraints];
    }

    return self;
}

- (void)setupViews {
    // Setup animating coin
    NSArray *imageNames = @[@"Coin1", @"Coin2", @"Coin3", @"Coin4", @"Coin5", @"Coin6"];
    NSMutableArray *images = [[NSMutableArray alloc] init];
    for (int i = 0; i < imageNames.count; i++) {
        [images addObject:[UIImage imageNamed:[imageNames objectAtIndex:i]]];
    }

    animatingCoin = [[UIImageView alloc] initWithFrame:CGRectMake(60, 95, 86, 193)];
    animatingCoin.animationImages = images;
    animatingCoin.animationDuration = 0.5;
    [animatingCoin startAnimating];

    // Setup plus minus indicator (indicates the direction of balance changes)
    plusMinusIndicator = [[UILabel alloc] init];
    plusMinusIndicator.alpha = 0;
    plusMinusIndicator.font = [UIFont systemFontOfSize:14.f];
    plusMinusIndicator.text = @"+"; // placeholder

    // Setup balance label
    balance = [[UILabel alloc] init];
    balance.backgroundColor = [UIColor clearColor];
    balance.font = [UIFont fontWithName:@"Bourbon-Oblique" size:18.f];
    balance.textAlignment = NSTextAlignmentCenter;
    balance.textColor = [UIColor blackColor];
    balance.userInteractionEnabled = NO;
}

- (void)addViews {
    [self addSubview:animatingCoin];
    [self addSubview:plusMinusIndicator];
    [self addSubview:balance];
}

- (void)setupLayoutConstraints {
    CGFloat coinSize = 22.f;
    animatingCoin.translatesAutoresizingMaskIntoConstraints = NO;
    [animatingCoin.heightAnchor constraintEqualToConstant:coinSize].active = YES;
    [animatingCoin.widthAnchor constraintEqualToConstant:coinSize].active = YES;
    [animatingCoin.centerYAnchor constraintEqualToAnchor:balance.centerYAnchor].active = YES;
    [animatingCoin.trailingAnchor constraintEqualToAnchor:balance.leadingAnchor constant:-2.5f].active = YES;

    plusMinusIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [plusMinusIndicator.centerYAnchor constraintEqualToAnchor:balance.centerYAnchor].active = YES;
    [plusMinusIndicator.trailingAnchor constraintEqualToAnchor:animatingCoin.leadingAnchor constant:-2.5f].active = YES;

    balance.translatesAutoresizingMaskIntoConstraints = NO;
    [balance.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [balance.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
}

#pragma mark - State Changes

- (void)bindWithModel:(PsiCashClientModel*)clientModel {
    double previousBalance = self.model.balanceInPsi;

    self.model = clientModel;

    if ([self.model hasAuthPackage]) {
        if ([self.model.authPackage hasIndicatorToken]) {
            balance.text = [NSString stringWithFormat:@"%.2f Psi", clientModel.balanceInNanoPsi / 1e9];

            BOOL shouldAnimate = YES;
            if (self.model.balanceInPsi > previousBalance) {
                plusMinusIndicator.text = [@"+" stringByAppendingFormat:@"%.2f", self.model.balanceInPsi - previousBalance];
                plusMinusIndicator.textColor = [UIColor greenColor];
            } else if (self.model.balanceInPsi < previousBalance) {
                plusMinusIndicator.text = [@"" stringByAppendingFormat:@"%.2f", self.model.balanceInPsi - previousBalance];;
                plusMinusIndicator.textColor = [UIColor redColor];
            } else {
                shouldAnimate = NO;
            }

            if (shouldAnimate) {
                NSTimeInterval fadeInOutTime = 0.5;

                [UIView animateWithDuration:fadeInOutTime animations:^{
                    plusMinusIndicator.alpha = 0.7;
                } completion:^(BOOL finished){
                    // TODO: check bool `finished`
                    [UIView animateWithDuration:fadeInOutTime animations:^{
                        plusMinusIndicator.alpha = 0;
                    }];
                }];
            }
        } else {
            assert(false); // TODO: user has no indicator token
        }
    } else {
        balance.text = @"Updating balance...";
    }
}

@end
