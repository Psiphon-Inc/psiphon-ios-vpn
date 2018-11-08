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

#import "OnboardingViewController.h"
#import "OnboardingView.h"
#import "UIColor+Additions.h"
#import "Asserts.h"

#define NumPages 3

@implementation OnboardingViewController {
    NSMutableArray<OnboardingView *> *onboardingViews;
    UIProgressView *progressView;

    int currentPage;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        currentPage = 1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;

    OnboardingView *page0 = [self getOnboardingViewForPage:0];
    [self.view addSubview:page0];

    UILayoutGuide *safeAreaLayoutGuide;
    if (@available(iOS 11.0, *)) {
        safeAreaLayoutGuide = self.view.safeAreaLayoutGuide;
    } else {
        safeAreaLayoutGuide = [[UILayoutGuide alloc] init];
    }

    page0.translatesAutoresizingMaskIntoConstraints = FALSE;
    [page0.topAnchor constraintEqualToAnchor:safeAreaLayoutGuide.topAnchor]
            .active = TRUE;
    [page0.bottomAnchor constraintEqualToAnchor:safeAreaLayoutGuide.bottomAnchor]
            .active = TRUE;
    [page0.leadingAnchor constraintEqualToAnchor:safeAreaLayoutGuide.leadingAnchor]
            .active = TRUE;
    [page0.trailingAnchor constraintEqualToAnchor:safeAreaLayoutGuide.trailingAnchor]
            .active = TRUE;

    progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    [self.view addSubview:progressView];
    progressView.progressTintColor = UIColor.lightishBlue;
    progressView.translatesAutoresizingMaskIntoConstraints = FALSE;

    [progressView.bottomAnchor
            constraintEqualToAnchor:safeAreaLayoutGuide.bottomAnchor].active = TRUE;
    [progressView.leadingAnchor
            constraintEqualToAnchor:safeAreaLayoutGuide.leadingAnchor].active = TRUE;
    [progressView.trailingAnchor
            constraintEqualToAnchor:safeAreaLayoutGuide.trailingAnchor].active = TRUE;
    [progressView.heightAnchor constraintEqualToConstant:6.f].active = TRUE;


    progressView.progress = (CGFloat)currentPage/(CGFloat)NumPages;
}

- (OnboardingView *)getOnboardingViewForPage:(int)page {
    switch (page) {
        case 0: return [[OnboardingView alloc]
                    initWithImage:[UIImage imageNamed:@"OnboardingStairs"]
                        withTitle:@"Beyond Borders"
                         withBody:@"Censored by your country, corporation, or campus? Psiphon is uniquely suited to help you get to the content you want, whenever and wherever you want it."
                withAccessoryView:nil];
                break;

        default:
            PSIAssert(FALSE);
            return nil;
    }
}

@end
