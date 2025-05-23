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

#import <Foundation/Foundation.h>
#import "MainViewController.h"
#import "AppInfo.h"
#import "AppDelegate.h"
#import "Asserts.h"
#import "DispatchUtils.h"
#import "Logging.h"
#import "DebugViewController.h"
#import "SharedConstants.h"
#import "NSString+Additions.h"
#import "UIAlertController+Additions.h"
#import "UpstreamProxySettings.h"
#import "RACCompoundDisposable.h"
#import "RACTuple.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"
#import "RACUnit.h"
#import "RegionSelectionButton.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"
#import "UILabel+GetLabelHeight.h"
#import "VPNStartAndStopButton.h"
#import "AlertDialogs.h"
#import "RACSignal+Operations2.h"
#import "NSDate+Comparator.h"
#import "PickerViewController.h"
#import "Strings.h"
#import "SkyRegionSelectionViewController.h"
#import "UIView+Additions.h"
#import "CloudsView.h"
#import "AppObservables.h"
#import "Psiphon-Swift.h"

PsiFeedbackLogType const MainViewControllerLogType = @"MainViewController";

@interface MainViewController ()

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@property (nonatomic, readonly) BOOL startVPNOnFirstLoad;

@end

@implementation MainViewController {
    // UI elements
    UILayoutGuide *viewWidthGuide;
    UILabel *statusLabel;
    UIButton *versionLabel;
    
    UIView *bottomBarBackground;
    CAGradientLayer *bottomBarBackgroundGradient;
    SubscriptionBarView *subscriptionBarView;
    
    RegionSelectionButton *regionSelectionButton;
    VPNStartAndStopButton *startAndStopButton;
    
    // UI Constraint
    NSLayoutConstraint *startButtonWidth;
    NSLayoutConstraint *startButtonHeight;
    
    // Settings
    AnimatedUIButton *settingsButton;

    // Psiphon Logo
    // Replaces the PsiCash UI when the user is subscribed
    UIImageView *psiphonLargeLogo;
    UIImageView *psiphonTitle;

    // PsiCash
    PsiCashWidgetView *psiCashWidget;

    // Clouds
    CloudsView* cloudBackgroundView;

}

// Force portrait orientation
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown);
}

// No heavy initialization should be done here, since RootContainerController
// expects this method to return immediately.
// All such initialization could be deferred to viewDidLoad callback.
- (id)initWithStartingVPN:(BOOL)startVPN {
    self = [super init];
if (self) {
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
        _startVPNOnFirstLoad = startVPN;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.compoundDisposable dispose];
}

#pragma mark - Lifecycle methods
- (void)viewDidLoad {
    LOG_DEBUG();
    [super viewDidLoad];
    
    // Setting up the UI
    // calls them in the right order
    [self.view setBackgroundColor:UIColor.darkBlueColor];
    [self setNeedsStatusBarAppearanceUpdate];
    [self setupWidthLayoutGuide];
    [self addViews];
    [self setupCloudsView];
    [self setupVersionLabel];
    [self setupPsiphonLogoView];
    [self setupPsiphonTitle];
    [self setupStartAndStopButton];
    [self setupStatusLabel];
    [self setupRegionSelectionButton];
    [self setupSettingsButton];
    [self setupBottomBarBackground];
    [self setupSubscriptionsBar];
    [self setupPsiCashWidgetView];

    MainViewController *__weak weakSelf = self;
    
    // Observe VPN status for updating UI state
    RACDisposable *tunnelStatusDisposable = [AppObservables.shared.vpnStatus
      subscribeNext:^(NSNumber *statusObject) {
          MainViewController *__strong strongSelf = weakSelf;
          if (strongSelf != nil) {

              VPNStatus s = (VPNStatus) [statusObject integerValue];
              [weakSelf updateUIConnectionState:s];

              // Notify SettingsViewController that the state has changed.
              // Note that this constant is used PsiphonClientCommonLibrary, and cannot simply be replaced by a RACSignal.
              // TODO: replace this notification with the appropriate signal.
              [[NSNotificationCenter defaultCenter] postNotificationName:kPsiphonConnectionStateNotification object:nil];
          }
      }];
    
    [self.compoundDisposable addDisposable:tunnelStatusDisposable];
    
    RACDisposable *vpnStartStatusDisposable = [[AppObservables.shared.vpnStartStopStatus
      deliverOnMainThread]
      subscribeNext:^(NSNumber *statusObject) {
          MainViewController *__strong strongSelf = weakSelf;
          if (strongSelf != nil) {
              VPNStartStopStatus startStatus = (VPNStartStopStatus) [statusObject integerValue];

              if (startStatus == VPNStartStopStatusPendingStart) {
                  [strongSelf->startAndStopButton setHighlighted:TRUE];
              } else {
                  [strongSelf->startAndStopButton setHighlighted:FALSE];
              }

              if (startStatus == VPNStartStopStatusFailedUserPermissionDenied) {

                  // Present the VPN permission denied alert.
                  UIAlertController *alert = [AlertDialogs vpnPermissionDeniedAlert];
                  [alert presentFromTopController];

              } else if (startStatus == VPNStartStopStatusInternetNotReachable) {
                  
                  // Alert the user that tunnel start failed due to no internet access.
                  [UIAlertController
                   presentSimpleAlertWithTitle:[UserStrings No_internet_alert_title]
                   message:[UserStrings No_internet_alert_body]
                   preferredStyle:UIAlertControllerStyleAlert
                   okHandler:nil];
                  
              } else if (startStatus == VPNStartStopStatusFailedOtherReason) {

                  // Alert the user that the VPN failed to start, and that they should try again.
                  [UIAlertController
                   presentSimpleAlertWithTitle:[UserStrings Unable_to_start_alert_title]
                   message:[UserStrings Error_while_start_psiphon_alert_body]
                   preferredStyle:UIAlertControllerStyleAlert
                   okHandler:nil];
              }
          }
      }];
    
    [self.compoundDisposable addDisposable:vpnStartStatusDisposable];


    // Subscribes to AppObservables.shared.subscriptionStatus signal.
    {
        __block RACDisposable *disposable = [AppObservables.shared.subscriptionStatus
                                             subscribeNext:^(BridgedUserSubscription *status) {
            MainViewController *__strong strongSelf = weakSelf;
            if (strongSelf != nil) {
                                
                if (status.state == BridgedSubscriptionStateUnknown) {
                    return;
                }

                BOOL showPsiCashUI = (status.state == BridgedSubscriptionStateInactive);
                [strongSelf setPsiCashContentHidden:!showPsiCashUI];
            }
        } error:^(NSError *error) {
            [weakSelf.compoundDisposable removeDisposable:disposable];
        } completed:^{
            [weakSelf.compoundDisposable removeDisposable:disposable];
        }];
        
        [self.compoundDisposable addDisposable:disposable];
    }
    
    // Subscribes to AppObservables.shared.subscriptionBarStatus signal.
    {
        __block RACDisposable *disposable = [AppObservables.shared.subscriptionBarStatus
                                             subscribeNext: ^(ObjcSubscriptionBarViewState *state) {
            MainViewController *__strong strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf->bottomBarBackgroundGradient.colors = state.backgroundGradientColors;
                [strongSelf->subscriptionBarView objcBind:state];
            }
        } error:^(NSError *error) {
            [weakSelf.compoundDisposable removeDisposable:disposable];
        } completed:^{
            [weakSelf.compoundDisposable removeDisposable:disposable];
        }];
        
        [self.compoundDisposable addDisposable:disposable];
    }

    // Updates PsiCashWidgetView with updated view model.
    {
        [self.compoundDisposable addDisposable:[AppObservables.shared.psiCashWidgetViewModel
                                subscribeNext:^(BridgedPsiCashWidgetBindingType * _Nullable newValue) {
            MainViewController *__strong strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->psiCashWidget objcBind:newValue];
            }
        }]];
    }

    // Observes selected server region.
    {
        [self.compoundDisposable addDisposable:
             [AppObservables.shared.selectedServerRegion subscribeNext:^(Region * _Nullable selectedRegion) {
            MainViewController *__strong strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->regionSelectionButton bind:selectedRegion];
            }
        }]
        ];
    }
    
    // Calls startStopVPN if startVPNOnFirstLoad is TRUE.
    {
        if (self.startVPNOnFirstLoad == TRUE) {
            [AppDelegate.sharedAppDelegate startStopVPN];
        }
    }
  
}

- (void)viewDidAppear:(BOOL)animated {
    LOG_DEBUG();
    [super viewDidAppear:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    LOG_DEBUG();
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    LOG_DEBUG();
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    LOG_DEBUG();
    [super viewDidDisappear:animated];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

// Reload when rotate
- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {

    [self setStartButtonSizeConstraints:size];
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    bottomBarBackgroundGradient.frame = bottomBarBackground.bounds;
}

#pragma mark - UI callbacks

- (void)onStartStopTap:(UIButton *)sender {
    [AppDelegate.sharedAppDelegate startStopVPN];
}

- (void)onSettingsButtonTap:(UIButton *)sender {
    [SwiftDelegate.bridge presentSettingsViewController];
}

- (void)onRegionSelectionButtonTap:(UIButton *)sender {
    SkyRegionSelectionViewController *regionViewController =
      [[SkyRegionSelectionViewController alloc] init];

    MainViewController *__weak weakSelf = self;

    regionViewController.selectionHandler =
      ^(NSUInteger selectedIndex, id selectedItem, PickerViewController *viewController) {
          MainViewController *__strong strongSelf = weakSelf;
          if (strongSelf != nil) {
              Region *selectedRegion = (Region *)selectedItem;
              [SwiftDelegate.bridge userSelectedRegion:selectedRegion];
              [viewController dismissViewControllerAnimated:TRUE completion:nil];
          }
      };

    PsiNavigationController *navController = [[PsiNavigationController alloc]
      initWithRootViewController:regionViewController applyPsiphonStyling:TRUE];
    [self presentViewController:navController animated:YES completion:nil];
}

#if DEBUG || DEV_RELEASE
- (void)onVersionLabelTap:(UIButton *)sender {
    DebugViewController *viewController = [[DebugViewController alloc] init];
    [self presentViewController:viewController animated:YES completion:nil];
}
#endif

# pragma mark - UI helper functions

- (NSString *)getVPNStatusDescription:(VPNStatus)status {
    switch(status) {
        case VPNStatusDisconnected: return UserStrings.Vpn_status_disconnected;
        case VPNStatusInvalid: return UserStrings.Vpn_status_invalid;
        case VPNStatusConnected: return UserStrings.Vpn_status_connected;
        case VPNStatusConnecting: return UserStrings.Vpn_status_connecting;
        case VPNStatusDisconnecting: return UserStrings.Vpn_status_disconnecting;
        case VPNStatusReasserting: return UserStrings.Vpn_status_reconnecting;
        case VPNStatusRestarting: return UserStrings.Vpn_status_restarting;
    }
    [PsiFeedbackLogger error:@"MainViewController unhandled VPNStatus (%ld)", (long)status];
    return nil;
}

- (void)setupSettingsButton {
    settingsButton.accessibilityIdentifier = @"settings"; // identifier for UI Tests

    [settingsButton addTarget:self action:@selector(onSettingsButtonTap:) forControlEvents:UIControlEventTouchUpInside];

    UIImage *gearTemplate = [UIImage imageNamed:@"DarkGear"];
    [settingsButton setImage:gearTemplate forState:UIControlStateNormal];

    // Setup autolayout
    settingsButton.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [settingsButton.topAnchor constraintEqualToAnchor:regionSelectionButton.topAnchor],
        [settingsButton.trailingAnchor constraintEqualToAnchor:viewWidthGuide.trailingAnchor],
        [settingsButton.widthAnchor constraintEqualToConstant:58.f],
        [settingsButton.heightAnchor constraintEqualToAnchor:regionSelectionButton.heightAnchor]
    ]];
}

- (void)updateUIConnectionState:(VPNStatus)s {
    [startAndStopButton setHighlighted:FALSE];
    
    if ([VPNStateCompat providerNotStoppedWithVpnStatus:s] && s != VPNStatusConnected) {
        [startAndStopButton setConnecting];
    }
    else if (s == VPNStatusConnected) {
        [startAndStopButton setConnected];
    }
    else {
        [startAndStopButton setDisconnected];
    }
    
    [self setStatusLabelText:[self getVPNStatusDescription:s]];
}

- (void)setupWidthLayoutGuide {
    viewWidthGuide = [[UILayoutGuide alloc] init];
    [self.view addLayoutGuide:viewWidthGuide];

    CGFloat viewMaxWidth = 360;
    CGFloat viewToParentWidthRatio = 0.87;

    // Sets the layout guide width to be a ratio of `self.view` width, but no larger
    // than `viewMaxWidth`.
    NSLayoutConstraint *widthConstraint;
    if (self.view.frame.size.width * viewToParentWidthRatio > viewMaxWidth) {
        widthConstraint = [viewWidthGuide.widthAnchor constraintEqualToConstant:viewMaxWidth];
    } else {
        widthConstraint = [viewWidthGuide.widthAnchor
                           constraintEqualToAnchor:self.view.safeWidthAnchor
                           multiplier:viewToParentWidthRatio];
    }

    [NSLayoutConstraint activateConstraints:@[
        widthConstraint,
        [viewWidthGuide.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
}

// Add all views at the same time so there are no crashes while
// adding and activating autolayout constraints.
- (void)addViews {
    
    NSLocale *currentLocale = [SwiftDelegate.bridge getLocaleForCurrentAppLanguage];
    
    cloudBackgroundView = [[CloudsView alloc] initForAutoLayout];
    versionLabel = [[UIButton alloc] init];
    settingsButton = [[AnimatedUIButton alloc] init];
    psiphonLargeLogo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PsiphonLogoWhite"]];
    psiphonTitle = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PsiphonTitle"]];
    psiCashWidget = [[PsiCashWidgetView alloc] initWithLocale:currentLocale];
    startAndStopButton = [VPNStartAndStopButton buttonWithType:UIButtonTypeCustom];
    statusLabel = [[UILabel alloc] init];
    regionSelectionButton = [[RegionSelectionButton alloc] init];
    regionSelectionButton.accessibilityIdentifier = @"regionSelectionButton"; // identifier for UI Tests
    bottomBarBackground = [[UIView alloc] init];
    subscriptionBarView = [SwiftDelegate.bridge makeSubscriptionBarView];

    // NOTE: some views overlap so the order they are added
    //       is important for user interaction.
    [self.view addSubview:cloudBackgroundView];
    [self.view addSubview:psiphonLargeLogo];
    [self.view addSubview:psiphonTitle];
    [self.view addSubview:psiCashWidget];
    [self.view addSubview:versionLabel];
    [self.view addSubview:settingsButton];
    [self.view addSubview:startAndStopButton];
    [self.view addSubview:statusLabel];
    [self.view addSubview:regionSelectionButton];
    [self.view addSubview:bottomBarBackground];
    [self.view addSubview:subscriptionBarView];
    
}

- (void)setupCloudsView {
    [NSLayoutConstraint activateConstraints:@[
        [cloudBackgroundView.topAnchor constraintEqualToAnchor:self.view.safeTopAnchor],
        [cloudBackgroundView.bottomAnchor constraintEqualToAnchor:subscriptionBarView.topAnchor],
        [cloudBackgroundView.leadingAnchor constraintEqualToAnchor:self.view.safeLeadingAnchor],
        [cloudBackgroundView.trailingAnchor constraintEqualToAnchor:self.view.safeTrailingAnchor],
    ]];
}

- (void)setupStartAndStopButton {
    startAndStopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [startAndStopButton addTarget:self action:@selector(onStartStopTap:) forControlEvents:UIControlEventTouchUpInside];
    
    // Setup autolayout
    [startAndStopButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [startAndStopButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:05].active = YES;

    [self setStartButtonSizeConstraints:self.view.bounds.size];
}

- (void)setStartButtonSizeConstraints:(CGSize)size {
    if (startButtonWidth) {
        startButtonWidth.active = NO;
    }

    if (startButtonHeight) {
        startButtonHeight.active = NO;
    }

    CGFloat startButtonMaxSize = 200;
    CGFloat startButtonSize = MIN(MIN(size.width, size.height)*0.388, startButtonMaxSize);
    startButtonWidth = [startAndStopButton.widthAnchor constraintEqualToConstant:startButtonSize];
    startButtonHeight = [startAndStopButton.heightAnchor constraintEqualToAnchor:startAndStopButton.widthAnchor];

    startButtonWidth.active = YES;
    startButtonHeight.active = YES;
}

- (void)setupStatusLabel {
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.adjustsFontSizeToFitWidth = YES;
    [self setStatusLabelText:[self getVPNStatusDescription:VPNStatusInvalid]];
    statusLabel.textAlignment = NSTextAlignmentCenter;
    statusLabel.textColor = UIColor.blueGreyColor;
    statusLabel.font = [UIFont avenirNextBold:14.5];
    
    // Setup autolayout
    CGFloat labelHeight = [statusLabel getLabelHeight];
    [statusLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;
    [statusLabel.topAnchor constraintEqualToAnchor:startAndStopButton.bottomAnchor constant:20].active = YES;
    [statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)setStatusLabelText:(NSString*)s {
    NSString *upperCased = [s uppercaseStringWithLocale:[SwiftDelegate.bridge getLocaleForCurrentAppLanguage]];
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc]
      initWithString:upperCased];

    [mutableStr addAttribute:NSKernAttributeName
                       value:@1.1
                       range:NSMakeRange(0, mutableStr.length)];
    statusLabel.attributedText = mutableStr;
}

- (void)setupRegionSelectionButton {
    [regionSelectionButton addTarget:self action:@selector(onRegionSelectionButtonTap:) forControlEvents:UIControlEventTouchUpInside];

    // Add constraints
    regionSelectionButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *idealBottomSpacing = [regionSelectionButton.bottomAnchor constraintEqualToAnchor:bottomBarBackground.topAnchor constant:-25.f];
    [idealBottomSpacing setPriority:999];

    [NSLayoutConstraint activateConstraints:@[
        idealBottomSpacing,
        [regionSelectionButton.topAnchor constraintGreaterThanOrEqualToAnchor:statusLabel.bottomAnchor
                                                                     constant:15.0],
        [regionSelectionButton.leadingAnchor constraintEqualToAnchor:viewWidthGuide.leadingAnchor],
        [regionSelectionButton.trailingAnchor constraintEqualToAnchor:settingsButton.leadingAnchor
                                                             constant:-10.f]
    ]];

}

- (void)setupVersionLabel {
    CGFloat padding = 10.0f;
    
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [versionLabel setTitle:[SwiftDelegate.bridge versionLabelText]
                  forState:UIControlStateNormal];

    [versionLabel setTitleColor:UIColor.nepalGreyBlueColor forState:UIControlStateNormal];
    versionLabel.titleLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.titleLabel.font = [UIFont avenirNextBold:12.f];
    versionLabel.userInteractionEnabled = FALSE;
    versionLabel.contentEdgeInsets = UIEdgeInsetsMake(padding, padding, padding, padding);

#if DEBUG || DEV_RELEASE
    versionLabel.userInteractionEnabled = TRUE;
    [versionLabel addTarget:self
                     action:@selector(onVersionLabelTap:)
           forControlEvents:UIControlEventTouchUpInside];
    
    if (AppInfo.runningUITest == TRUE) {
        // Hide the version label when generating screenshots.
        versionLabel.hidden = YES;
    }
#endif
    
    NSLayoutConstraint *trailingConstraint;
    if (@available(iOS 11.0, *)) {
        trailingConstraint = [versionLabel.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor
                                                                         constant:-15.f];
    } else {
        trailingConstraint = [versionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                                         constant:padding + 15.f];
    }
    
    // Setup autolayout
    [NSLayoutConstraint activateConstraints:@[
      trailingConstraint,
      [versionLabel.topAnchor constraintEqualToAnchor:psiphonTitle.topAnchor constant:-padding]
    ]];
}

- (void)setupBottomBarBackground {
    bottomBarBackground.translatesAutoresizingMaskIntoConstraints = NO;
    bottomBarBackground.backgroundColor = [UIColor clearColor];
    
    // Setup autolayout
    [NSLayoutConstraint activateConstraints:@[
      [bottomBarBackground.topAnchor constraintEqualToAnchor:subscriptionBarView.topAnchor],
      [bottomBarBackground.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
      [bottomBarBackground.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
      [bottomBarBackground.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    bottomBarBackgroundGradient = [CAGradientLayer layer];
    bottomBarBackgroundGradient.frame = bottomBarBackground.bounds; // frame reset in viewDidLayoutSubviews

    [bottomBarBackground.layer insertSublayer:bottomBarBackgroundGradient atIndex:0];
}

- (void)setupSubscriptionsBar {
    // Setup autolayout
    subscriptionBarView.translatesAutoresizingMaskIntoConstraints = FALSE;

    NSLayoutConstraint *maxHeightConstraint = [subscriptionBarView.heightAnchor
                                               constraintLessThanOrEqualToAnchor:self.view.safeHeightAnchor
                                               multiplier:0.14];
    
    maxHeightConstraint.priority = UILayoutPriorityDefaultHigh;
    maxHeightConstraint.active = TRUE;
    
    [NSLayoutConstraint activateConstraints:@[
        [subscriptionBarView.centerXAnchor constraintEqualToAnchor:bottomBarBackground.centerXAnchor],
        [subscriptionBarView.centerYAnchor constraintEqualToAnchor:bottomBarBackground.safeCenterYAnchor],
        [subscriptionBarView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [subscriptionBarView.heightAnchor constraintGreaterThanOrEqualToConstant:90.0]
    ]];

}

#pragma mark - PsiCash UI

- (void)psiCashAccountButtonTapped {
    [SwiftDelegate.bridge presentPsiCashAccountViewControllerWithPsiCashScreen:TRUE];
}

- (void)speedBoostButtonTapped {
    [SwiftDelegate.bridge presentPsiCashStoreViewController:PsiCashScreenTabSpeedBoost];
}

- (void)setupPsiphonLogoView {
    psiphonLargeLogo.translatesAutoresizingMaskIntoConstraints = NO;
    psiphonLargeLogo.contentMode = UIViewContentModeScaleAspectFill;

    CGFloat offset = 40.f;

    if (@available(iOS 11.0, *)) {
        [psiphonLargeLogo.centerXAnchor
         constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor].active = TRUE;
    } else {
        [psiphonLargeLogo.centerXAnchor
         constraintEqualToAnchor:self.view.centerXAnchor].active = TRUE;
    }
    
    [psiphonLargeLogo.topAnchor
     constraintEqualToAnchor:psiphonTitle.bottomAnchor
     constant:offset].active = TRUE;
}

- (void)setupPsiphonTitle {
    psiphonTitle.translatesAutoresizingMaskIntoConstraints = NO;
    psiphonTitle.contentMode = UIViewContentModeScaleAspectFit;
    
    CGFloat topPadding = 15.0;
    CGFloat leadingPadding = 15.0;
    
    if (@available(iOS 11.0, *)) {
        [NSLayoutConstraint activateConstraints:@[
            [psiphonTitle.leadingAnchor
             constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor
             constant:leadingPadding],
            [psiphonTitle.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
            constant:topPadding]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [psiphonTitle.leadingAnchor
             constraintEqualToAnchor:self.view.leadingAnchor
             constant:leadingPadding],
            [psiphonTitle.topAnchor
            constraintEqualToAnchor:self.view.topAnchor
            constant:topPadding + 20]
        ]];
    }
}

- (void)setupPsiCashWidgetView {
    psiCashWidget.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [psiCashWidget.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [psiCashWidget.topAnchor constraintEqualToAnchor:psiphonTitle.bottomAnchor
                                                constant:25.0],
        [psiCashWidget.leadingAnchor constraintEqualToAnchor:viewWidthGuide.leadingAnchor],
        [psiCashWidget.trailingAnchor constraintEqualToAnchor:viewWidthGuide.trailingAnchor]
    ]];

    [psiCashWidget.psiCashAccountButton addTarget:self
                                           action:@selector(psiCashAccountButtonTapped)
                                 forControlEvents:UIControlEventTouchUpInside];
    
    [psiCashWidget.speedBoostButton addTarget:self
                                       action:@selector(speedBoostButtonTapped)
                             forControlEvents:UIControlEventTouchUpInside];
    
    // Sets accessibilityIdentifier for PsiphonUITests
    psiCashWidget.speedBoostButton.accessibilityIdentifier = @"psiCashWidgetSpeedBoostButton";
    
    // Makes balance view tappable
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self
                                             action:@selector(addPsiCashButtonTapped)];
    [psiCashWidget.balanceViewWrapper.view addGestureRecognizer:tapRecognizer];
}

- (void)setPsiCashContentHidden:(BOOL)hidden {
    psiCashWidget.hidden = hidden;
    psiCashWidget.userInteractionEnabled = !hidden;

    // Show Psiphon large logo and hide Psiphon small logo when PsiCash is hidden.
    psiphonLargeLogo.hidden = !hidden;
    psiphonTitle.hidden = hidden;
}

@end
