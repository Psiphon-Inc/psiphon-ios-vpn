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

#import <ReactiveObjC/RACSignal.h>
#import "OnboardingViewController.h"
#import "OnboardingView.h"
#import "UIColor+Additions.h"
#import "Asserts.h"
#import "SkyButton.h"
#import "RingSkyButton.h"
#import "UIFont+Additions.h"
#import "UIViewController+Additions.h"
#import "RoyalSkyButton.h"
#import "VPNManager.h"
#import "ArrowView.h"
#import "RACCompoundDisposable.h"
#import "AlertDialogs.h"
#import "UIAlertController+Additions.h"
#import "OnboardingScrollableView.h"
#import "Strings.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "ContainerDB.h"

const int NumPages = 4;

@interface OnboardingViewController ()

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation OnboardingViewController {
    UIProgressView *progressView;
    UIButton *nextPageButton;
    int currentPage;

    UIView *currentOnboardingView;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        currentPage = 0;
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }
    return self;
}

- (void)dealloc {
    [self.compoundDisposable dispose];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;

    // Progress view
    {
        progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        [self.view addSubview:progressView];
        progressView.progressTintColor = UIColor.lightishBlue;

        progressView.translatesAutoresizingMaskIntoConstraints = FALSE;
        [progressView.bottomAnchor
          constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor].active = TRUE;
        [progressView.leadingAnchor
          constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor].active = TRUE;
        [progressView.trailingAnchor
          constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor].active = TRUE;
        [progressView.heightAnchor constraintEqualToConstant:6.f].active = TRUE;
    }

    // Next button
    {
        nextPageButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.view addSubview:nextPageButton];
        [nextPageButton setTitle:[Strings nextPageButtonTitle] forState:UIControlStateNormal];
        [nextPageButton setTitleColor:UIColor.paleGreyThreeColor forState:UIControlStateNormal];
        nextPageButton.titleLabel.font = [UIFont avenirNextDemiBold:14.f];
        [nextPageButton addTarget:self
                 action:@selector(gotoNextPage)
       forControlEvents:UIControlEventTouchUpInside];

        nextPageButton.translatesAutoresizingMaskIntoConstraints = FALSE;
        [nextPageButton.bottomAnchor constraintEqualToAnchor:progressView.topAnchor
                                          constant:-20.f].active = TRUE;
        [nextPageButton.trailingAnchor
          constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor
                         constant:-40.f].active = TRUE;
    }

    UIView *firstPage = [self getOnboardingViewForPage:currentPage];
    [self setCurrentOnboardingPage:firstPage];
}

#pragma mark - Page update methods

- (void)setCurrentOnboardingPage:(UIView *_Nonnull)onboardingPage {
    progressView.progress = (CGFloat) (currentPage + 1) / (CGFloat) NumPages;

    if (currentOnboardingView) {
        [currentOnboardingView removeFromSuperview];
    }

    currentOnboardingView = onboardingPage;
    [self.view addSubview:currentOnboardingView];
    [self applyOnboardingViewConstraintsToView:currentOnboardingView];
}

- (UIView *_Nullable)getOnboardingViewForPage:(int)page {
    UIView *v;

    switch (page) {
        case 0: {
            // Language selection page
            RingSkyButton *selectLangButton = [[RingSkyButton alloc] initForAutoLayout];
            selectLangButton.includeChevron = TRUE;
            [selectLangButton setTitle:[Strings onboardingSelectLanguageButtonTitle]];
            [selectLangButton addTarget:self
                                 action:@selector(onLanguageSelectionButton)
                       forControlEvents:UIControlEventTouchUpInside];

            v = [[OnboardingView alloc]
              initWithImage:[UIImage imageNamed:@"OnboardingStairs"]
                  withTitle:[Strings onboardingBeyondBordersHeaderText]
                   withBody:[Strings onboardingBeyondBordersBodyText]
          withAccessoryView:selectLangButton];
            break;
        }
        case 1: {
            // Privacy Policy page
            RoyalSkyButton *acceptButton = [[RoyalSkyButton alloc] initForAutoLayout];
            [acceptButton setTitle:[Strings acceptButtonTitle]];
            [acceptButton addTarget:self
                             action:@selector(onPrivacyPolicyAccepted)
                   forControlEvents:UIControlEventTouchUpInside];
            acceptButton.shadow = TRUE;

            RingSkyButton *declineButton = [[RingSkyButton alloc] initForAutoLayout];
            [declineButton setTitle:[Strings declineButtonTitle]];
            [declineButton addTarget:self
                              action:@selector(onPrivacyPolicyDeclined)
                    forControlEvents:UIControlEventTouchUpInside];

            UIStackView *buttonsView = [[UIStackView alloc]
              initWithArrangedSubviews:@[declineButton, acceptButton]];
            buttonsView.spacing = 20.f;
            buttonsView.distribution = UIStackViewDistributionFillEqually;

            v = [[OnboardingScrollableView alloc]
              initWithImage:[UIImage imageNamed:@"OnboardingPrivacyPolicy"]
                  withTitle:[Strings privacyPolicyTitle]
                   withBody:[Strings privacyPolicyHTMLText]
          withAccessoryView:buttonsView];

            break;
        }
        case 2: {
            // "Getting Started" page
            v = [[OnboardingView alloc]
              initWithImage:[UIImage imageNamed:@"OnboardingPermission"]
                  withTitle:[Strings onboardingGettingStartedHeaderText]
                   withBody:[Strings onboardingGettingStartedBodyText]
          withAccessoryView:nil];
            break;
        }
        //
        case 3: {
            v = [self createInstallGuideVPNOnboardingView];
            break;
        }

        default:
            return nil;
    }

    return v;
}

- (void)gotoNextPage {
    OnboardingViewController *__weak weakSelf = self;

    currentPage++;

    if (currentPage == 1 || currentPage == NumPages - 1) {
        nextPageButton.hidden = TRUE;
    } else {
        nextPageButton.hidden = FALSE;
    }

    // Present the next onboarding page. If none is available notify the delegate
    // that the onboarding has finished.
    UIView *_Nullable newPage = [self getOnboardingViewForPage:currentPage];
    if (newPage) {
        [self setCurrentOnboardingPage:newPage];
    } else {
        if (self.delegate) {
            [self.delegate onboardingFinished:self];
        }
        return;
    }

    // Prompt user for VPN configuration permission on page2.
    if (currentPage == 3) {
        // Hide next button for second page.
        nextPageButton.hidden = TRUE;

        __block RACDisposable *disposable = [[[VPNManager sharedInstance] reinstallVPNConfiguration]
          subscribeNext:^(RACUnit *x) {
              // Go to next onboarding page.
              [weakSelf gotoNextPage];
          }
          error:^(NSError *error) {
              // Go to previous page.
              nextPageButton.hidden = FALSE;
              currentPage--;
              UIView *prvPage = [weakSelf getOnboardingViewForPage:currentPage];
              [weakSelf setCurrentOnboardingPage:prvPage];

              // If the error was due to user denying permission to install VPN configuration,
              // shows the `vpnPermissionDeniedAlert` instead of the generic operation failed alert.
              if ([error.domain isEqualToString:NEVPNErrorDomain] &&
                  error.code == NEVPNErrorConfigurationReadWriteFailed &&
                  [error.localizedDescription isEqualToString:@"permission denied"] ) {

                  // Present the VPN permission denied alert.
                  UIAlertController *alert = [AlertDialogs vpnPermissionDeniedAlert];
                  [weakSelf presentViewController:alert animated:TRUE completion:nil];

              } else {
                  UIAlertController *alert = [AlertDialogs genericOperationFailedTryAgain];
                  [weakSelf presentViewController:alert animated:TRUE completion:nil];
              }
              [weakSelf.compoundDisposable removeDisposable:disposable];
          }
          completed:^{
              [weakSelf.compoundDisposable removeDisposable:disposable];
          }];

        [self.compoundDisposable addDisposable:disposable];
    }
}

#pragma mark - UI callbacks

- (void)onLanguageSelectionButton {
}

- (void)onPrivacyPolicyAccepted {
    [[[ContainerDB alloc] init] setAcceptedCurrentPrivacyPolicy];

    // Go to next page;
    [self gotoNextPage];
}

- (void)onPrivacyPolicyDeclined {
    // Only alert the user that they need to accept the privacy policy.
    UIAlertController *alert = [AlertDialogs privacyPolicyDeclinedAlert];
    [self presentViewController:alert animated:TRUE completion:nil];
}

#pragma mark - View helper methods

// Creates view with an arrow pointing to "Allow" button of permission dialog.
// The X and Y center of the returned view is expected to match the X and Y center of the screen.
- (UIView *)createInstallGuideVPNOnboardingView {
    UIView *view = [[UIView alloc] init];

    ArrowView *arrow = [[ArrowView alloc] initWithFrame:CGRectZero];
    [view addSubview:arrow];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = [Strings vpnInstallGuideText];
    [view addSubview:label];

    label.adjustsFontSizeToFitWidth = TRUE;
    label.minimumScaleFactor = 0.8;
    label.font = [UIFont avenirNextMedium:16.f];
    label.textColor = UIColor.greyishBrown;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;

    arrow.translatesAutoresizingMaskIntoConstraints = FALSE;
    [arrow.heightAnchor constraintEqualToConstant:54.f].active = TRUE;
    [arrow.widthAnchor constraintEqualToConstant:30.f].active = TRUE;
    [arrow.centerXAnchor constraintEqualToAnchor:view.centerXAnchor constant:-60.f].active = TRUE;
    [arrow.centerYAnchor constraintEqualToAnchor:view.centerYAnchor constant:160.f].active = TRUE;

    label.translatesAutoresizingMaskIntoConstraints = FALSE;
    [label.topAnchor constraintEqualToAnchor:arrow.bottomAnchor constant:10.f].active = TRUE;
    [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor].active = TRUE;
    [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor].active = TRUE;
    [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor].active = TRUE;

    return view;
}

- (void)applyOnboardingViewConstraintsToView:(UIView *)view {
    view.translatesAutoresizingMaskIntoConstraints = FALSE;
    [view.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor].active = TRUE;
    [view.bottomAnchor constraintEqualToAnchor:nextPageButton.topAnchor].active = TRUE;
    [view.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor
                                       constant:20.f].active = TRUE;
    [view.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor
                                        constant:-20.f].active = TRUE;
}

@end
