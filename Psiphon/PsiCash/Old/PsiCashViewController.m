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

#import "PsiCashViewController.h"

#import "PsiCashBalanceView.h"
#import "PsiCashClient.h"
#import "PsiCashInfoView.h"
#import "PsiCashSpeedBoostView.h"
#import "PsiCashEarningOptionsView.h"

@interface PsiCashViewController ()

@end

@implementation PsiCashViewController {
    UIStackView *stackView;
    UIStackView *stackView1;
    UIStackView *stackView2;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    if (size.width > size.height) {
        stackView.axis = UILayoutConstraintAxisHorizontal;
        stackView.distribution = UIStackViewDistributionFillEqually;
    } else {
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.distribution = UIStackViewDistributionFillProportionally;
    }

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    }];

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}


- (void)viewDidLoad {
    [super viewDidLoad];

    if (!_openedFromSettings) {
        NSString* rightButtonTitle = NSLocalizedStringWithDefaultValue(@"DONE_ACTION", nil, [NSBundle mainBundle], @"Done", @"Title of the button that dismisses the subscriptions menu");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                                                  initWithTitle:rightButtonTitle
                                                  style:UIBarButtonItemStyleDone
                                                  target:self
                                                  action:@selector(dismissViewController)];
    }

    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor colorWithRed:0.26 green:0.26 blue:0.26 alpha:1.0];

    CGFloat titleHeight = 30.f; //40.f;

    // Balance Title
    UILabel *balanceTitle = [[UILabel alloc] init];
    balanceTitle.backgroundColor = [UIColor colorWithRed:0.40 green:0.40 blue:0.40 alpha:1.0];
    balanceTitle.text = @"- Balance -"; // TODO: localize
    balanceTitle.textColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    balanceTitle.textAlignment = NSTextAlignmentCenter;
    [balanceTitle.heightAnchor constraintEqualToConstant:titleHeight].active = YES;

    // Balance View
    PsiCashBalanceView *balanceView = [[PsiCashBalanceView alloc] init];
    [balanceView.heightAnchor constraintEqualToConstant:titleHeight*2].active = YES;

    // What's PsiCash Title
    UILabel *whatsPsiCashTitle = [[UILabel alloc] init];
    whatsPsiCashTitle.backgroundColor = [UIColor colorWithRed:0.40 green:0.40 blue:0.40 alpha:1.0]; // TODO: function
    whatsPsiCashTitle.text = @"- What's PsiCash? -"; // TODO: localize
    whatsPsiCashTitle.textColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    whatsPsiCashTitle.textAlignment = NSTextAlignmentCenter;
    [whatsPsiCashTitle.heightAnchor constraintEqualToConstant:titleHeight].active = YES;

    // What's PsiCash View
    UIView *whatsPsiCashView = [[PsiCashInfoView alloc] init];
//    [whatsPsiCashView.heightAnchor constraintEqualToConstant:40.f].active = YES;

    // Spacer View 1
    UIView *spacerView1  = [[UIView alloc] init];

    // SpeedBoost Title
    UILabel *speedBoostTitle = [[UILabel alloc] init];
    speedBoostTitle.backgroundColor = [UIColor colorWithRed:0.82 green:0.43 blue:0.41 alpha:1.0];
    speedBoostTitle.text = @"- SpeedBoost -"; // TODO: localize
    speedBoostTitle.textColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    speedBoostTitle.textAlignment = NSTextAlignmentCenter;
    [speedBoostTitle.heightAnchor constraintEqualToConstant:titleHeight].active = YES;

    // SpeedBoost View
    UIView *speedBoostView = [[PsiCashSpeedBoostView alloc] init];

    // Earn PsiCash Title
    UILabel *earnPsiCashTitle = [[UILabel alloc] init];
    earnPsiCashTitle.backgroundColor = [UIColor colorWithRed:0.40 green:0.40 blue:0.40 alpha:1.0];
    earnPsiCashTitle.text = @"- Earn PsiCash -"; // TODO: localize
    earnPsiCashTitle.textColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    earnPsiCashTitle.textAlignment = NSTextAlignmentCenter;
    [earnPsiCashTitle.heightAnchor constraintEqualToConstant:titleHeight].active = YES;

    // Earn PsiCash View
    UIView *earnPsiCashView = [[PsiCashEarningOptionsView alloc] init];
//    [earnPsiCashView.heightAnchor constraintEqualToConstant:62.f].active = YES;

    // Spacer View 2
    UIView *spacerView2  = [[UIView alloc] init];

    // Setup stackViews
    stackView1 = [[UIStackView alloc] init];
    stackView1.translatesAutoresizingMaskIntoConstraints = NO;
    stackView2 = [[UIStackView alloc] init];
    stackView2.translatesAutoresizingMaskIntoConstraints = NO;

    stackView = [[UIStackView alloc] init];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView addArrangedSubview:stackView1];
    [stackView addArrangedSubview:stackView2];

    [stackView1 addArrangedSubview:balanceTitle];
    [stackView1 addArrangedSubview:balanceView];
    [stackView1 addArrangedSubview:speedBoostTitle];
    [stackView1 addArrangedSubview:speedBoostView];

//    [stackView1 addArrangedSubview:spacerView1];
    [stackView2 addArrangedSubview:earnPsiCashTitle];
    [stackView2 addArrangedSubview:earnPsiCashView];
//    [stackView2 addArrangedSubview:whatsPsiCashTitle];
//    [stackView2 addArrangedSubview:whatsPsiCashView];
//    [stackView2 addArrangedSubview:spacerView2];

    stackView1.axis = UILayoutConstraintAxisVertical; // TODO
    stackView1.distribution = UIStackViewDistributionFill;
    stackView1.alignment = UIStackViewAlignmentFill;

    stackView2.axis = UILayoutConstraintAxisVertical; // TODO
    stackView2.distribution = UIStackViewDistributionFill;
    stackView2.alignment = UIStackViewAlignmentFill;

    stackView.axis = UILayoutConstraintAxisVertical; // TODO
    stackView.distribution = UIStackViewDistributionFillEqually;
    stackView.alignment = UIStackViewAlignmentFill;
//    stackView.spacing = 16.f;


    [self.view addSubview:stackView];
    [stackView.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor].active = YES;
    [stackView.bottomAnchor constraintEqualToAnchor:self.bottomLayoutGuide.bottomAnchor].active = YES;
    [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
}

- (void)dismissViewController {
    if (_openedFromSettings) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
