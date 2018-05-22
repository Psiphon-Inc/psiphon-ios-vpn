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

#import "AppDelegate.h"
#import "PsiCashOnboardingViewController.h"
#import "PsiCashOnboardingInfoViewController.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "UILabel+GetLabelHeight.h"


#define kNumOnboardingViews 3
#define kSubtitleFontName @"SanFranciscoDisplay-Regular"


@implementation PsiCashOnboardingViewController {
    // UI elements
    UILabel *appTitleLabel;
    UILabel *appSubTitleLabel;
    UIButton *nextButton;

    BOOL isRTL;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

// Force portrait orientation
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    isRTL = ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);

    [self addAppTitleLabel];
    [self addAppSubTitleLabel];

    /* Customize UIPageControl */
    UIPageControl *pageControl = [UIPageControl appearance];
    pageControl.pageIndicatorTintColor = [UIColor colorWithRed:0.00 green:0.00 blue:0.00 alpha:.34f];
    pageControl.currentPageIndicatorTintColor = [UIColor whiteColor];
    pageControl.backgroundColor = [UIColor clearColor];
    pageControl.opaque = NO;

    /* Setup UIPageViewController */
    self.pageController = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:nil];
    self.pageController.dataSource = self;
    self.pageController.delegate = self;

    /* Setup and present initial PsiCashOnboardingChildViewController */
    UIViewController<PsiCashOnboardingChildViewController> *initialViewController = [self viewControllerAtIndex:0];
    NSArray *viewControllers = [NSArray arrayWithObject:initialViewController];
    [self setBackgroundColourForIndex:0];

    [self.view addSubview:self.pageController.view];
    [self.pageController didMoveToParentViewController:self];

    [self.pageController setViewControllers:viewControllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    [self addChildViewController:self.pageController];

    self.pageController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pageController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [self.pageController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [self.pageController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.pageController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;

    /* Add static views to OnboardingViewController */

    /* Setup skip button */
    nextButton = [[UIButton alloc] init];
    [nextButton setTitle:NSLocalizedStringWithDefaultValue(@"ONBOARDING_NEXT_BUTTON", nil, [NSBundle mainBundle], @"NEXT", @"Text of button at the bottom right or left (depending on rtl) of the onboarding screens which allows the user to move on to the next onboarding screen. Note: should be all uppercase (capitalized) when possible.") forState:UIControlStateNormal];
    [nextButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [nextButton.titleLabel setFont:[UIFont boldSystemFontOfSize:14]];
    [nextButton.titleLabel setAdjustsFontSizeToFitWidth:YES];

    [nextButton addTarget:self
                   action:@selector(moveToNextPage)
         forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:nextButton];
    nextButton.translatesAutoresizingMaskIntoConstraints = NO;

    id <UILayoutSupport> bottomLayoutGuide =  self.bottomLayoutGuide;

    NSDictionary *viewsDictionary = @{
                                      @"bottomLayoutGuide": bottomLayoutGuide,
                                      @"nextButton": nextButton,
                                      };

    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[nextButton]-[bottomLayoutGuide]" options:0 metrics:nil views:viewsDictionary]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[nextButton]-|" options:0 metrics:nil views:viewsDictionary]];

    UITapGestureRecognizer *tutorialPress =
    [[UITapGestureRecognizer alloc] initWithTarget:self
                                            action:@selector(moveToNextPage)];
    [self.view addGestureRecognizer:tutorialPress];
}


- (void)addAppTitleLabel {
    appTitleLabel = [[UILabel alloc] init];
    appTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appTitleLabel.text = @"PSIPHON";
    appTitleLabel.textAlignment = NSTextAlignmentCenter;
    appTitleLabel.textColor = [UIColor whiteColor];
    CGFloat narrowestWidth = self.view.frame.size.width;
    if (self.view.frame.size.height < self.view.frame.size.width) {
        narrowestWidth = self.view.frame.size.height;
    }
    appTitleLabel.font = [UIFont fontWithName:@"Bourbon-Oblique" size:narrowestWidth * 0.10625f];
    if ([PsiphonClientCommonLibraryHelpers unsupportedCharactersForFont:appTitleLabel.font.fontName withString:appTitleLabel.text]) {
        appTitleLabel.font = [UIFont systemFontOfSize:narrowestWidth * 0.075f];
    }

    [self.view addSubview:appTitleLabel];

    // Setup autolayout
    CGFloat labelHeight = [appTitleLabel getLabelHeight];
    [appTitleLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;

    NSLayoutConstraint *floatingVerticallyConstraint =[NSLayoutConstraint constraintWithItem:appTitleLabel
                                                                                   attribute:NSLayoutAttributeBottom
                                                                                   relatedBy:NSLayoutRelationEqual
                                                                                      toItem:self.view
                                                                                   attribute:NSLayoutAttributeBottom
                                                                                  multiplier:.14
                                                                                    constant:0];
    // This constraint will be broken in case the next constraint can't be enforced
    floatingVerticallyConstraint.priority = 999;
    [self.view addConstraint:floatingVerticallyConstraint];

    [appTitleLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.topAnchor].active = YES;
    [appTitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)addAppSubTitleLabel {
    appSubTitleLabel = [[UILabel alloc] init];
    appSubTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appSubTitleLabel.text = NSLocalizedStringWithDefaultValue(@"APP_SUB_TITLE_MAIN_VIEW", nil, [NSBundle mainBundle], @"BEYOND BORDERS", @"Text for app subtitle on main view.");
    appSubTitleLabel.textAlignment = NSTextAlignmentCenter;
    appSubTitleLabel.textColor = [UIColor whiteColor];
    CGFloat narrowestWidth = self.view.frame.size.width;
    if (self.view.frame.size.height < self.view.frame.size.width) {
        narrowestWidth = self.view.frame.size.height;
    }
    appSubTitleLabel.font = [UIFont fontWithName:@"Bourbon-Oblique" size:narrowestWidth * 0.10625f/2.0f];
    if ([PsiphonClientCommonLibraryHelpers unsupportedCharactersForFont:appSubTitleLabel.font.fontName withString:appSubTitleLabel.text]) {
        appSubTitleLabel.font = [UIFont systemFontOfSize:narrowestWidth * 0.075f/2.0f];
    }

    [self.view addSubview:appSubTitleLabel];

    // Setup autolayout
    CGFloat labelHeight = [appSubTitleLabel getLabelHeight];
    [appSubTitleLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;
    [appSubTitleLabel.topAnchor constraintEqualToAnchor:appTitleLabel.bottomAnchor].active = YES;
    [appSubTitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)setNavButtonTitle {
    UIViewController <PsiCashOnboardingChildViewController>*presentedViewController = [_pageController.viewControllers objectAtIndex:0];

    if (presentedViewController.index == PsiCashOnboardingPage3Index) {
        [nextButton setTitle:NSLocalizedStringWithDefaultValue(@"ONBOARDING_DONE_BUTTON", nil, [NSBundle mainBundle], @"DONE", @"Text of button at the bottom right or left (depending on rtl) of the last onboarding screen which allows the user to finish the onboarding sequence. Note: should be all uppercase (capitalized) when possible.") forState:UIControlStateNormal];
    } else {
        [nextButton setTitle:NSLocalizedStringWithDefaultValue(@"ONBOARDING_NEXT_BUTTON", nil, [NSBundle mainBundle], @"NEXT", @"Text of button at the bottom right or left (depending on rtl) of the onboarding screens which allows the user to move on to the next onboarding screen. Note: should be all uppercase (capitalized) when possible.") forState:UIControlStateNormal];
    }
}


#pragma mark - UIPageViewControllerDelegate methods and helper functions

- (void)setBackgroundColourForIndex:(NSInteger)index {
    if (index == PsiCashOnboardingPage1Index) {
        self.view.layer.contents = (id)[UIImage imageNamed:@"PsiCash_Onboarding_Background_1"].CGImage;
    } else if (index == PsiCashOnboardingPage2Index) {
        self.view.layer.contents = (id)[UIImage imageNamed:@"PsiCash_Onboarding_Background_2"].CGImage;
    } else if (index == PsiCashOnboardingPage3Index) {
        self.view.layer.contents = (id)[UIImage imageNamed:@"PsiCash_Onboarding_Background_3"].CGImage;
    }
}

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers transitionCompleted:(BOOL)completed {
    [self setNavButtonTitle];
    UIViewController <PsiCashOnboardingChildViewController>*presentedViewController = [_pageController.viewControllers objectAtIndex:0];
    [self setBackgroundColourForIndex:presentedViewController.index];
}

- (void)pageViewController:(UIPageViewController *)pageViewController willTransitionToViewControllers:(NSArray<UIViewController *> *)pendingViewControllers {
    UIViewController <PsiCashOnboardingChildViewController>*pendingViewController = (UIViewController <PsiCashOnboardingChildViewController> *)[pendingViewControllers objectAtIndex:0];
    [self setBackgroundColourForIndex:pendingViewController.index];
}


- (NSInteger)getCurrentPageIndex {
    if ([_pageController.viewControllers count] == 0) {
        return 0;
    }

    UIViewController <PsiCashOnboardingChildViewController>*presentedViewController = [_pageController.viewControllers objectAtIndex:0];
    return presentedViewController.index;
}

#pragma mark - UIPageViewControllerDataSource methods and helper functions

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController {

    NSUInteger index = [(UIViewController <PsiCashOnboardingChildViewController>*)viewController index];

    if (index == 0) {
        return nil;
    }

    index--;

    return [self viewControllerAtIndex:index];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController {

    NSUInteger index = [(UIViewController <PsiCashOnboardingChildViewController>*)viewController index];

    index++;

    if (index == kNumOnboardingViews) {
        return nil;
    }

    return [self viewControllerAtIndex:index];
}

- (UIViewController <PsiCashOnboardingChildViewController>*)viewControllerAtIndex:(NSUInteger)index {
    UIViewController<PsiCashOnboardingChildViewController> *childViewController;
    childViewController = [[PsiCashOnboardingInfoViewController alloc] init];
    childViewController.delegate = self;
    childViewController.index = index;

    return childViewController;
}

- (NSInteger)presentationCountForPageViewController:(UIPageViewController *)pageViewController {
    // The number of items in the UIPageControl
    return kNumOnboardingViews;
}

- (NSInteger)presentationIndexForPageViewController:(UIPageViewController *)pageViewController {
    // The selected dot in the UIPageControl
    return [self getCurrentPageIndex];
}

#pragma mark - PsiCashOnboardingChildViewController delegate methods

- (CGFloat)getTitleOffset {
    return appSubTitleLabel.frame.origin.y + appSubTitleLabel.frame.size.height;
}

- (void)moveToNextPage {
    [self moveToViewAtIndex:[self getCurrentPageIndex]+1];
}

- (void)moveToViewAtIndex:(NSInteger)index {
    if (index >= kNumOnboardingViews) {
        [self onboardingEnded];
    } else {
        __weak PsiCashOnboardingViewController *weakSelf = self;
        [self.pageController setViewControllers:@[[self viewControllerAtIndex:index]] direction:isRTL ? UIPageViewControllerNavigationDirectionReverse : UIPageViewControllerNavigationDirectionForward animated:NO completion:^(BOOL finished) {
            [weakSelf setNavButtonTitle];
            UIViewController <PsiCashOnboardingChildViewController>*presentedViewController = [weakSelf.pageController.viewControllers objectAtIndex:0];
            [weakSelf setBackgroundColourForIndex:presentedViewController.index];
        }];
    }
}

- (void)onboardingEnded {
    id<PsiCashOnboardingViewControllerDelegate> strongDelegate = self.delegate;

    if ([strongDelegate respondsToSelector:@selector(onboardingEnded)]) {
        [strongDelegate onboardingEnded];
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
