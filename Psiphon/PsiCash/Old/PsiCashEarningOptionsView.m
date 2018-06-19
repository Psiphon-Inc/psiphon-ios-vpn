/*
 * Copyright (c) 2017, Psiphon Inc.
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

#import "PsiCashEarningOptionsView.h"
#import "PsiCashClient.h"

@implementation PsiCashEarningOptionsView {
    UILabel *info;
    UIButton *visitPsiCashWebsite;
    UIStackView *stackView;
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
    stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 10.f;

    info = [[UILabel alloc] init];
    info.adjustsFontSizeToFitWidth = YES;
    info.font = [UIFont systemFontOfSize:14.f];
    info.numberOfLines = 0;
    info.text = @"Earning PsiCash allows you to use SpeedBoost and more!";
    info.textColor = [UIColor whiteColor];
    info.textAlignment = NSTextAlignmentCenter;

    // TOOD: cleanup
    visitPsiCashWebsite = [[UIButton alloc] init];
    [visitPsiCashWebsite setTitle:@"Start earning PsiCash!" forState:UIControlStateNormal];
    [visitPsiCashWebsite.titleLabel setFont:[UIFont systemFontOfSize:16.f]];
    [visitPsiCashWebsite setContentEdgeInsets:UIEdgeInsetsMake(5, 5, 5, 5)];
    [visitPsiCashWebsite setBackgroundColor:[UIColor colorWithRed:0.40 green:0.40 blue:0.40 alpha:1.0]];
    [visitPsiCashWebsite.layer setCornerRadius:5.f];
    [visitPsiCashWebsite.layer setBorderColor:[UIColor colorWithRed:0.45 green:0.47 blue:0.64 alpha:1.0].CGColor];
    [visitPsiCashWebsite.layer setBorderWidth:1.f];

    [visitPsiCashWebsite addTarget:self action:@selector(startDemoMode) forControlEvents:UIControlEventTouchUpInside];
}

- (void)addViews {
    [self addSubview:stackView];
    [stackView addArrangedSubview:[UIView new]]; // TODO: is this a hack?
    [stackView addArrangedSubview:info];
    [stackView addArrangedSubview:visitPsiCashWebsite];
    [stackView addArrangedSubview:[UIView new]];
}

-  (void)setupLayoutConstraints {
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
    [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
    [stackView.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;

    info.translatesAutoresizingMaskIntoConstraints = NO;
    [info.centerXAnchor constraintEqualToAnchor:stackView.centerXAnchor].active = YES;
    [info.widthAnchor constraintEqualToAnchor:stackView.widthAnchor multiplier:0.75].active = YES;

    visitPsiCashWebsite.translatesAutoresizingMaskIntoConstraints = NO;
    [visitPsiCashWebsite.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
}

# pragma mark - demo mode functions
- (void)startDemoMode {
//    [[PsiCashClient sharedInstance] enterDemoMode];
    [visitPsiCashWebsite setTitle:@"You're earning PsiCash now!" forState:UIControlStateNormal];
}

@end
