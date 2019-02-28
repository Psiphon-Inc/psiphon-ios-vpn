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
#import "SkyButton.h"
#import "RingSkyButton.h"
#import "UIFont+Additions.h"
#import "RoyalSkyButton.h"
#import "VPNManager.h"
#import "RACCompoundDisposable.h"
#import "AlertDialogs.h"
#import "UIView+Additions.h"
#import "OnboardingScrollableView.h"
#import "Strings.h"
#import "ContainerDB.h"
#import "LanguageSelectionViewController.h"
#import "AppDelegate.h"
#import "CloudsView.h"
#import "Logging.h"

const int NumPages = 4;

@interface OnboardingViewController ()

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation OnboardingViewController {
    CloudsView *cloudsView;
    UIProgressView *progressView;
    UIButton *nextPageButton;

    UIView *currentOnboardingView;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }
    return self;
}

- (void)dealloc {
    [self.compoundDisposable dispose];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setNeedsStatusBarAppearanceUpdate];

    self.view.backgroundColor = UIColor.darkBlueColor;

    // Clouds view
    {
        cloudsView = [[CloudsView alloc] initForAutoLayout];
        [self.view addSubview:cloudsView];
        [NSLayoutConstraint activateConstraints:@[
          [cloudsView.topAnchor constraintEqualToAnchor:self.view.safeTopAnchor],
          [cloudsView.leadingAnchor constraintEqualToAnchor:self.view.safeLeadingAnchor],
          [cloudsView.trailingAnchor constraintEqualToAnchor:self.view.safeTrailingAnchor],
          [cloudsView.bottomAnchor constraintEqualToAnchor:self.view.safeBottomAnchor]
        ]];
    }

    // Progress view
    {
        progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        [self.view addSubview:progressView];
        progressView.progressTintColor = UIColor.lightishBlue;

        progressView.translatesAutoresizingMaskIntoConstraints = FALSE;
        [NSLayoutConstraint activateConstraints:@[
          [progressView.bottomAnchor constraintEqualToAnchor:self.view.safeBottomAnchor],
          [progressView.leadingAnchor constraintEqualToAnchor:self.view.safeLeadingAnchor],
          [progressView.trailingAnchor constraintEqualToAnchor:self.view.safeTrailingAnchor],
          [progressView.heightAnchor constraintEqualToConstant:6.f]
        ]];
    }

    // Next button
    {
        nextPageButton = [UIButton buttonWithType:UIButtonTypeSystem];
        CGFloat p = 20.f; // Margin around the next button.
        nextPageButton.contentEdgeInsets = UIEdgeInsetsMake(p, 2.f * p, p, p);

        [nextPageButton setTitle:[Strings nextPageButtonTitle] forState:UIControlStateNormal];
        [nextPageButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        nextPageButton.titleLabel.font = [UIFont avenirNextDemiBold:16.f];
        [nextPageButton addTarget:self
                 action:@selector(gotoNextPage)
       forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:nextPageButton];

        nextPageButton.translatesAutoresizingMaskIntoConstraints = FALSE;
        [NSLayoutConstraint activateConstraints:@[
          [nextPageButton.bottomAnchor constraintEqualToAnchor:progressView.topAnchor],
          [nextPageButton.trailingAnchor constraintEqualToAnchor:self.view.safeTrailingAnchor
                                                        constant:-20.f],
        ]];
    }

    UIView *firstPage = [self createOnboardingViewForPage:1];
    [self setCurrentOnboardingPage:firstPage];
}

#pragma mark - Page update methods

- (void)setCurrentOnboardingPage:(UIView *_Nonnull)onboardingPage {
    progressView.progress = (CGFloat) (onboardingPage.tag) / (CGFloat) NumPages;

    if (onboardingPage.tag == 1 ||
        onboardingPage.tag == NumPages - 1) {
        nextPageButton.hidden = FALSE;
    } else {
        nextPageButton.hidden = TRUE;
    }

    if (currentOnboardingView) {
        [currentOnboardingView removeFromSuperview];
    }

    currentOnboardingView = onboardingPage;
    [self.view addSubview:currentOnboardingView];
    [self applyOnboardingViewConstraintsToView:currentOnboardingView
                  anchorBottomToNextPageButton:!nextPageButton.hidden];
}

- (UIView *_Nullable)createOnboardingViewForPage:(NSInteger)page {
    UIView *v;

    switch (page) {
        case 1: {
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
        case 2: {
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
        case 3: {
            // "Getting Started" page
            v = [[OnboardingView alloc]
              initWithImage:[UIImage imageNamed:@"OnboardingPermission"]
                  withTitle:[Strings onboardingGettingStartedHeaderText]
                   withBody:[Strings onboardingGettingStartedBodyText]
          withAccessoryView:nil];
            break;
        }
        //
        case 4: {
            v = [self createInstallGuideVPNOnboardingView];
            break;
        }

        default:
            return nil;
    }

    v.tag = page;
    return v;
}

- (void)gotoNextPage {
    OnboardingViewController *__weak weakSelf = self;

    // Present the next onboarding page. If none is available notify the delegate
    // that the onboarding has finished.
    UIView *_Nullable newPage = [self createOnboardingViewForPage:currentOnboardingView.tag + 1];
    if (newPage) {
        [self setCurrentOnboardingPage:newPage];
    } else {
        if (self.delegate) {
            [self.delegate onboardingFinished:self];
        }
        return;
    }

    // Prompt user for VPN configuration permission on page 4.
    if (newPage.tag == 4) {

        __block RACDisposable *disposable = [[[VPNManager sharedInstance] reinstallVPNConfiguration]
          subscribeNext:^(RACUnit *x) {
              // Go to next onboarding page.
              [weakSelf gotoNextPage];
          }
          error:^(NSError *error) {
              // Go to previous page.
              UIView *prvPage = [weakSelf createOnboardingViewForPage:3];
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

    LanguageSelectionViewController *vc = [[LanguageSelectionViewController alloc]
      initWithSupportedLanguages];

    vc.selectionHandler = ^(NSUInteger selectedIndex, id selectedItem,
      PickerViewController *viewController) {
        [viewController dismissViewControllerAnimated:TRUE completion:nil];
        // Reload the onboarding to reflect the newly selected language.
        [[AppDelegate sharedAppDelegate] reloadOnboardingViewController];
    };

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];

    [self presentViewController:nav animated:TRUE completion:nil];
}

- (void)onPrivacyPolicyAccepted {
    // Stores the privacy policy date that the user accepted.
    ContainerDB *containerDB = [[ContainerDB alloc] init];
    [containerDB setAcceptedPrivacyPolicyUnixTime:[containerDB privacyPolicyLastUpdateTime]];
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

    UIImage *arrowImage = [UIImage imageNamed:@"PermissionArrow"];
    UIImageView *arrowView = [[UIImageView alloc] initWithImage:arrowImage];
    [view addSubview:arrowView];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = [Strings vpnInstallGuideText];
    [view addSubview:label];

    label.adjustsFontSizeToFitWidth = TRUE;
    label.minimumScaleFactor = 0.8;
    label.font = [UIFont avenirNextMedium:16.f];
    label.textColor = UIColor.whiteColor;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;

    CGFloat aspectRatio = (arrowImage.size.width / arrowImage.size.height);
    arrowView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
      [arrowView.heightAnchor constraintEqualToConstant:84.f],
      [arrowView.widthAnchor constraintEqualToAnchor:arrowView.heightAnchor multiplier:aspectRatio],
      [arrowView.centerXAnchor constraintEqualToAnchor:view.centerXAnchor constant:-60.f],
      [arrowView.centerYAnchor constraintEqualToAnchor:view.centerYAnchor constant:160.f]
    ]];

    label.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
      [label.topAnchor constraintEqualToAnchor:arrowView.bottomAnchor constant:10.f],
      [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
      [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
      [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor]
    ]];

    return view;
}

- (void)applyOnboardingViewConstraintsToView:(UIView *)view
                anchorBottomToNextPageButton:(BOOL)anchorToNextPageButton {

    view.translatesAutoresizingMaskIntoConstraints = FALSE;

    NSLayoutConstraint *bottomConstraint;

    if (anchorToNextPageButton) {
        bottomConstraint = [view.bottomAnchor constraintEqualToAnchor:nextPageButton.topAnchor];
    } else {
        bottomConstraint = [view.bottomAnchor constraintEqualToAnchor:progressView.topAnchor
                                                             constant:-20.f];
    }

    [NSLayoutConstraint activateConstraints:@[
      bottomConstraint,
      [view.topAnchor constraintEqualToAnchor:self.view.safeTopAnchor constant:15.f],
      [view.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
      [view.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeLeadingAnchor],
      [view.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeTrailingAnchor],
      [view.widthAnchor constraintLessThanOrEqualToConstant:500.f]  // Max width for large screens.
    ]];
}

@end
