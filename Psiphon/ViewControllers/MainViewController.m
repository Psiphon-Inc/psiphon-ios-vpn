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
#import <PsiphonTunnel/PsiphonTunnel.h>
#import "MainViewController.h"
#import "AdManager.h"
#import "AppInfo.h"
#import "AppDelegate.h"
#import "Asserts.h"
#import "AvailableServerRegions.h"
#import "DispatchUtils.h"
#import "FeedbackManager.h"
#import "IAPViewController.h"
#import "Logging.h"
#import "DebugViewController.h"
#import "PsiphonConfigUserDefaults.h"
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
#import "SubscriptionsBar.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"
#import "UILabel+GetLabelHeight.h"
#import "VPNStartAndStopButton.h"
#import "AlertDialogs.h"
#import "RACSignal+Operations2.h"
#import "ContainerDB.h"
#import "NSDate+Comparator.h"
#import "PickerViewController.h"
#import "Strings.h"
#import "SkyRegionSelectionViewController.h"
#import "UIView+Additions.h"
#import "AppObservables.h"
#import <PersonalizedAdConsent/PersonalizedAdConsent.h>

PsiFeedbackLogType const MainViewControllerLogType = @"MainViewController";

#if DEBUG
NSTimeInterval const MaxAdLoadingTime = 1.f;
#else
NSTimeInterval const MaxAdLoadingTime = 10.f;
#endif

@interface MainViewController ()

@property (nonatomic) RACCompoundDisposable *compoundDisposable;
@property (nonatomic) AdManager *adManager;

@property (nonatomic, readonly) BOOL startVPNOnFirstLoad;

@end

@implementation MainViewController {
    // Models
    AvailableServerRegions *availableServerRegions;

    // UI elements
    UILayoutGuide *viewWidthGuide;
    UILabel *statusLabel;
    UIButton *versionLabel;
    SubscriptionsBar *subscriptionsBar;
    RegionSelectionButton *regionSelectionButton;
    VPNStartAndStopButton *startAndStopButton;
    
    // UI Constraint
    NSLayoutConstraint *startButtonWidth;
    NSLayoutConstraint *startButtonHeight;
    
    // Settings
    PsiphonSettingsViewController *appSettingsViewController;
    AnimatedUIButton *settingsButton;
    
    // Region Selection
    UIView *bottomBar;
    CAGradientLayer *bottomBarGradient;

    FeedbackManager *feedbackManager;

    // Psiphon Logo
    // Replaces the PsiCash UI when the user is subscribed
    UIImageView *psiphonLargeLogo;
    UIImageView *psiphonTitle;
    NoConnectionBannerView *noConnectionBannerView;

    // PsiCash
    PsiCashWidgetView *psiCashWidget;

    // Clouds
    UIImageView *cloudMiddleLeft;
    UIImageView *cloudMiddleRight;
    UIImageView *cloudTopRight;
    UIImageView *cloudBottomRight;
    NSLayoutConstraint *cloudMiddleLeftHorizontalConstraint;
    NSLayoutConstraint *cloudMiddleRightHorizontalConstraint;
    NSLayoutConstraint *cloudTopRightHorizontalConstraint;
    NSLayoutConstraint *cloudBottomRightHorizontalConstraint;
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
        
        _adManager = [AdManager sharedInstance];

        feedbackManager = [[FeedbackManager alloc] init];

        // TODO: remove persistance form init function.
        [self persistSettingsToSharedUserDefaults];
        
        _openSettingImmediatelyOnViewDidAppear = FALSE;

        _startVPNOnFirstLoad = startVPN;

        [RegionAdapter sharedInstance].delegate = self;
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

    // Check privacy policy accepted date.
    {
        // `[ContainerDB privacyPolicyLastUpdateTime]` should be equal to `[ContainerDB lastAcceptedPrivacyPolicy]`.
        // Log error if this is not the case.
        ContainerDB *containerDB = [[ContainerDB alloc] init];

        if (![containerDB hasAcceptedLatestPrivacyPolicy]) {
            NSDictionary *jsonDescription = @{@"event": @"PrivacyPolicyDateMismatch",
              @"got": [PsiFeedbackLogger safeValue:[containerDB lastAcceptedPrivacyPolicy]],
              @"expected": [containerDB privacyPolicyLastUpdateTime]};

            [PsiFeedbackLogger errorWithType:MainViewControllerLogType json:jsonDescription];
        }
    }

    availableServerRegions = [[AvailableServerRegions alloc] init];
    [availableServerRegions sync];
    
    // Setting up the UI
    // calls them in the right order
    [self.view setBackgroundColor:UIColor.darkBlueColor];
    [self setNeedsStatusBarAppearanceUpdate];
    [self setupWidthLayoutGuide];
    [self addViews];
    [self setupClouds];
    [self setupVersionLabel];
    [self setupPsiphonLogoView];
    [self setupPsiphonTitle];
    [self setupNoConnectionBannerView];
    [self setupStartAndStopButton];
    [self setupStatusLabel];
    [self setupRegionSelectionButton];
    [self setupSettingsButton];
    [self setupBottomBar];
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


    // Subscribes to AppDelegate subscription signal.
    __block RACDisposable *disposable = [[AppObservables.shared.subscriptionStatus
      deliverOnMainThread]
      subscribeNext:^(BridgedUserSubscription *status) {
          MainViewController *__strong strongSelf = weakSelf;
          if (strongSelf != nil) {


              if (status.state == BridgedSubscriptionStateUnknown) {
                  return;
              }

              [strongSelf->subscriptionsBar subscriptionActive:(status.state == BridgedSubscriptionStateActive)];

              BOOL showPsiCashUI = (status.state == BridgedSubscriptionStateInactive);
              [strongSelf setPsiCashContentHidden:!showPsiCashUI];
          }
      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];

    // Subscribes to `AppDelegate.psiCashBalance` subject to receive PsiCash balance updates.
    {
        [self.compoundDisposable addDisposable:[AppObservables.shared.psiCashBalance
                                subscribeNext:^(BridgedBalanceViewBindingType * _Nullable balance) {
            MainViewController *__strong strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->psiCashWidget.balanceView objcBind:balance];
            }
        }]];
    }

    // Subscribes to `AppObservable.shared.speedBoostExpiry` subject
    // to update `psiCashWidget` with the latest expiry time.
    {
        [self.compoundDisposable addDisposable:[AppObservables.shared.speedBoostExpiry
                                                subscribeNext:^(NSDate * _Nullable expiry) {
            MainViewController *__strong strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->psiCashWidget.speedBoostButton setExpiryTime:expiry];
            }
        }]];
    }

    // Observes reachability status.
    {
        [self.compoundDisposable addDisposable:
         [AppObservables.shared.reachabilityStatus subscribeNext:^(NSNumber * _Nullable statusObj) {
            MainViewController *__strong strongSelf = weakSelf;
            if (strongSelf) {
                NetworkStatus networkStatus = (NetworkStatus)[statusObj integerValue];
                if (networkStatus == NotReachable) {
                    [strongSelf->noConnectionBannerView setHidden: FALSE];
                } else {
                    [strongSelf->noConnectionBannerView setHidden: TRUE];
                }
            }
        }]];
    }
    
    // Calls startStopVPN if startVPNOnFirstLoad is TRUE.
    {
        if (self.startVPNOnFirstLoad == TRUE) {
            [AppDelegate.sharedAppDelegate startStopVPNWithAd:FALSE];
        }
    }
    
    // Initializes AdManager.
    {
        [[AdManager sharedInstance] initializeAdManager];
        [[AdManager sharedInstance] initializeRewardedVideos];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    LOG_DEBUG();
    [super viewDidAppear:animated];
    // Available regions may have changed in the background
    // TODO: maybe have availableServerRegions listen to a global signal?
    [availableServerRegions sync];
    [regionSelectionButton update];
    
    if (self.openSettingImmediatelyOnViewDidAppear) {
        [self openSettingsMenu];
        self.openSettingImmediatelyOnViewDidAppear = FALSE;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    bottomBarGradient.frame = bottomBar.bounds;
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

#pragma mark - Public properties

- (RACSignal<RACUnit *> *)activeStateLoadingSignal {
    
    // If MainViewController is started from onboarding, dismisses launch screen.
    if (self.startVPNOnFirstLoad == TRUE) {
        return [RACSignal return:RACUnit.defaultUnit];
    }
    
    // unsubscribedAdLoadingSignal if tunneled emits unit value when
    // untunneled interstitial ad had loaded or when MaxAdLoadingTime has passed,
    // otherwise, emits unit value immediately.
    RACSignal<RACUnit *> *unsubscribedAdLoadingSignal = [[[AppObservables.shared.vpnStatus
      map:^RACSignal * _Nullable(NSNumber * _Nullable value) {
        VPNStatus s = (VPNStatus) value.integerValue;
        
        if (s == VPNStatusDisconnected || s == VPNStatusInvalid) {
            
            
            return [[[[AdManager.sharedInstance.adSDKStarted
                       flattenMap:^__kindof RACSignal * _Nullable(RACUnit * _Nullable value) {
                
                // Ad SDK has loaded and consent collected.
                return [AdManager.sharedInstance.untunneledInterstitialLoadStatus
                        filter:^BOOL(NSNumber *loadStatus) {
                    AdLoadStatus status = (AdLoadStatus) [loadStatus integerValue];
                    return status == AdLoadStatusDone;
                }];
            }] merge:[RACSignal timer:MaxAdLoadingTime]]
                     take:1]
                    mapReplace:RACUnit.defaultUnit];
            
        } else {
            return [RACSignal return:RACUnit.defaultUnit];
        }
    }] switchToLatest] take:1];

    // subscriptionLoadingSignal emits a value when the user subscription status becomes known.
    RACSignal *subscriptionLoadingSignal = [[AppObservables.shared.subscriptionStatus
      filter:^BOOL(BridgedUserSubscription *status) {
        return status.state != BridgedSubscriptionStateUnknown;
      }]
      take:1];

    // Returned signal emits RACUnit and completes immediately after all loading operations
    // are done.
    return [subscriptionLoadingSignal flattenMap:^RACSignal *(BridgedUserSubscription *status) {
        BOOL subscribed = (status.state == BridgedSubscriptionStateActive);

        if (subscribed) {
            // User is subscribed, dismiss the loading screen immediately.
            return [RACSignal return:RACUnit.defaultUnit];
        } else {
            // User is not subscribed, wait for the adsLoadingSignal.
            return unsubscribedAdLoadingSignal;
        }
    }];
}

#pragma mark - UI callbacks

- (void)onStartStopTap:(UIButton *)sender {
    [AppDelegate.sharedAppDelegate startStopVPNWithAd:TRUE];
}

- (void)onSettingsButtonTap:(UIButton *)sender {
    [self openSettingsMenu];
}

- (void)onRegionSelectionButtonTap:(UIButton *)sender {
    NSString *selectedRegionCodeSnapshot = [[RegionAdapter sharedInstance] getSelectedRegion].code;

    SkyRegionSelectionViewController *regionViewController =
      [[SkyRegionSelectionViewController alloc] init];

    MainViewController *__weak weakSelf = self;

    regionViewController.selectionHandler =
      ^(NSUInteger selectedIndex, id selectedItem, PickerViewController *viewController) {
          MainViewController *__strong strongSelf = weakSelf;
          if (strongSelf != nil) {

              Region *selectedRegion = (Region *)selectedItem;

              [[RegionAdapter sharedInstance] setSelectedRegion:selectedRegion.code];

              if (![NSString stringsBothEqualOrNil:selectedRegion.code b:selectedRegionCodeSnapshot]) {
                  [strongSelf persistSelectedRegion];
                  [strongSelf->regionSelectionButton update];
                  [SwiftDelegate.bridge restartVPNIfActive];
              }

              [viewController dismissViewControllerAnimated:TRUE completion:nil];
          }
      };

    UINavigationController *navController = [[UINavigationController alloc]
      initWithRootViewController:regionViewController];
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)onSubscriptionTap {
    [self openIAPViewController];
}

#if DEBUG
- (void)onVersionLabelTap:(UIButton *)sender {
    DebugViewController *viewController = [[DebugViewController alloc] initWithCoder:nil];
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
    [self positionClouds:s];

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
    UIImage *cloud = [UIImage imageNamed:@"cloud"];
    cloudMiddleLeft = [[UIImageView alloc] initWithImage:cloud];
    cloudMiddleRight = [[UIImageView alloc] initWithImage:cloud];
    cloudTopRight = [[UIImageView alloc] initWithImage:cloud];
    cloudBottomRight = [[UIImageView alloc] initWithImage:cloud];
    versionLabel = [[UIButton alloc] init];
    settingsButton = [[AnimatedUIButton alloc] init];
    psiphonLargeLogo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PsiphonLogoWhite"]];
    psiphonTitle = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PsiphonTitle"]];
    noConnectionBannerView = [[NoConnectionBannerView alloc] init];
    psiCashWidget = [[PsiCashWidgetView alloc] initWithFrame:CGRectZero];
    startAndStopButton = [VPNStartAndStopButton buttonWithType:UIButtonTypeCustom];
    statusLabel = [[UILabel alloc] init];
    regionSelectionButton = [[RegionSelectionButton alloc] init];
    regionSelectionButton.accessibilityIdentifier = @"regionSelectionButton"; // identifier for UI Tests
    bottomBar = [[UIView alloc] init];
    subscriptionsBar = [[SubscriptionsBar alloc] init];

    // NOTE: some views overlap so the order they are added
    //       is important for user interaction.
    [self.view addSubview:cloudMiddleLeft];
    [self.view addSubview:cloudMiddleRight];
    [self.view addSubview:cloudTopRight];
    [self.view addSubview:cloudBottomRight];
    [self.view addSubview:psiphonLargeLogo];
    [self.view addSubview:psiphonTitle];
    [self.view addSubview:psiCashWidget];
    [self.view addSubview:versionLabel];
    [self.view addSubview:settingsButton];
    [self.view addSubview:startAndStopButton];
    [self.view addSubview:statusLabel];
    [self.view addSubview:regionSelectionButton];
    [self.view addSubview:bottomBar];
    [self.view addSubview:subscriptionsBar];
    [self.view addSubview:noConnectionBannerView];
}

- (void)setupClouds {

    UIImage *cloud = [UIImage imageNamed:@"cloud"];

    cloudMiddleLeft.translatesAutoresizingMaskIntoConstraints = NO;
    [cloudMiddleLeft.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor].active = YES;
    [cloudMiddleLeft.heightAnchor constraintEqualToConstant:cloud.size.height].active = YES;
    [cloudMiddleLeft.widthAnchor constraintEqualToConstant:cloud.size.width].active = YES;

    cloudMiddleRight.translatesAutoresizingMaskIntoConstraints = NO;
    [cloudMiddleRight.centerYAnchor constraintEqualToAnchor:cloudMiddleLeft.centerYAnchor].active = YES;
    [cloudMiddleRight.heightAnchor constraintEqualToConstant:cloud.size.height].active = YES;
    [cloudMiddleRight.widthAnchor constraintEqualToConstant:cloud.size.width].active = YES;

    cloudTopRight.translatesAutoresizingMaskIntoConstraints = NO;
    [cloudTopRight.topAnchor constraintEqualToAnchor:psiCashWidget.bottomAnchor constant:-20].active = YES;
    [cloudTopRight.heightAnchor constraintEqualToConstant:cloud.size.height].active = YES;
    [cloudTopRight.widthAnchor constraintEqualToConstant:cloud.size.width].active = YES;

    cloudBottomRight.translatesAutoresizingMaskIntoConstraints = NO;
    [cloudBottomRight.centerYAnchor constraintEqualToAnchor:regionSelectionButton.topAnchor constant:-24].active = YES;
    [cloudBottomRight.heightAnchor constraintEqualToConstant:cloud.size.height].active = YES;
    [cloudBottomRight.widthAnchor constraintEqualToConstant:cloud.size.width].active = YES;

    // Default horizontal positioning for clouds
    cloudMiddleLeftHorizontalConstraint = [cloudMiddleLeft.centerXAnchor constraintEqualToAnchor:self.view.leftAnchor constant:0];
    cloudMiddleRightHorizontalConstraint = [cloudMiddleRight.centerXAnchor constraintEqualToAnchor:self.view.rightAnchor constant:0]; // hide at first
    cloudTopRightHorizontalConstraint = [cloudTopRight.centerXAnchor constraintEqualToAnchor:self.view.rightAnchor constant:0];
    cloudBottomRightHorizontalConstraint = [cloudBottomRight.centerXAnchor constraintEqualToAnchor:self.view.rightAnchor constant:0];

    cloudMiddleLeftHorizontalConstraint.active = YES;
    cloudMiddleRightHorizontalConstraint.active = YES;
    cloudTopRightHorizontalConstraint.active = YES;
    cloudBottomRightHorizontalConstraint.active = YES;
}

- (void)positionClouds:(VPNStatus)s {

    // DEBUG: use to debug animations in slow motion (e.g. 20)
    CGFloat animationTimeStretchFactor = 1;

    static VPNStatus previousState = VPNStatusInvalid;

    CGFloat cloudWidth = [UIImage imageNamed:@"cloud"].size.width;

    // All clouds are centered on their respective side.
    // Use these variables to make slight adjustments to
    // each cloud's position.
    CGFloat cloudMiddleLeftOffset = 0;
    CGFloat cloudTopRightOffset = 0;
    CGFloat cloudBottomRightOffset = 15;

    // Remove all on-going cloud animations
    void (^removeAllCloudAnimations)(void) = ^void(void) {
        [self->cloudMiddleLeft.layer removeAllAnimations];
        [self->cloudMiddleRight.layer removeAllAnimations];
        [self->cloudTopRight.layer removeAllAnimations];
        [self->cloudBottomRight.layer removeAllAnimations];
    };

    // Position clouds in their default positions
    void (^disconnectedAndConnectedLayout)(void) = ^void(void) {
        self->cloudMiddleLeftHorizontalConstraint.constant = cloudMiddleLeftOffset;
        self->cloudMiddleRightHorizontalConstraint.constant = cloudWidth/2; // hidden
        self->cloudTopRightHorizontalConstraint.constant = cloudTopRightOffset;
        self->cloudBottomRightHorizontalConstraint.constant = cloudBottomRightOffset;
        [self.view layoutIfNeeded];
    };

    if ([VPNStateCompat providerNotStoppedWithVpnStatus:s] && s != VPNStatusConnected
        && s != VPNStatusRestarting) {
        // Connecting

        CGFloat cloudMiddleLeftHorizontalTranslation = -cloudWidth; // hidden
        CGFloat cloudMiddleRightHorizontalTranslation = -1.f/6 * cloudWidth + cloudMiddleLeftOffset;
        CGFloat cloudTopRightHorizontalTranslation = -3.f/4 * self.view.frame.size.width + cloudTopRightOffset;
        CGFloat cloudBottomRightHorizontalTranslation = -3.f/4 * self.view.frame.size.width + cloudBottomRightOffset;

        CGFloat maxTranslation = MAX(ABS(cloudMiddleLeftHorizontalTranslation), ABS(cloudMiddleRightHorizontalTranslation));
        maxTranslation = MAX(maxTranslation, MAX(ABS(cloudTopRightHorizontalTranslation),ABS(cloudBottomRightHorizontalTranslation)));

        void (^connectingLayout)(void) = ^void(void) {
            self->cloudMiddleLeftHorizontalConstraint.constant = cloudMiddleLeftHorizontalTranslation;
            self->cloudMiddleRightHorizontalConstraint.constant = cloudMiddleRightHorizontalTranslation;
            self->cloudTopRightHorizontalConstraint.constant = cloudTopRightHorizontalTranslation;
            self->cloudBottomRightHorizontalConstraint.constant = cloudBottomRightHorizontalTranslation;
            [self.view layoutIfNeeded];
        };

        cloudMiddleRightHorizontalConstraint.constant = maxTranslation - cloudWidth/2;
        [self.view layoutIfNeeded];

        if (!([VPNStateCompat providerNotStoppedWithVpnStatus:previousState]
              && previousState != VPNStatusConnected)
              && previousState != VPNStatusInvalid /* don't animate if the app was just opened */ ) {

            removeAllCloudAnimations();

            [UIView animateWithDuration:0.5 * animationTimeStretchFactor delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                connectingLayout();
            } completion:nil];
        } else {
            connectingLayout();
        }
    }
    else if (s == VPNStatusConnected) {

        if (previousState != VPNStatusConnected
            && previousState != VPNStatusInvalid /* don't animate if the app was just opened */ ) {

            // Connected

            removeAllCloudAnimations();

            [UIView animateWithDuration:0.25 * animationTimeStretchFactor delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{

                self->cloudMiddleLeftHorizontalConstraint.constant = -cloudWidth; // hidden
                self->cloudMiddleRightHorizontalConstraint.constant = cloudWidth/2 + cloudMiddleLeftOffset;
                self->cloudTopRightHorizontalConstraint.constant = -self.view.frame.size.width - cloudWidth/2 + cloudTopRightOffset;
                self->cloudBottomRightHorizontalConstraint.constant = -self.view.frame.size.width - cloudWidth/2 + cloudBottomRightOffset;
                [self.view layoutIfNeeded];

            } completion:^(BOOL finished) {

                if (finished) {
                    // We want all the clouds to animate at the same speed so we put them all at the
                    // same distance from their final point.
                    CGFloat maxOffset = MAX(MAX(ABS(cloudMiddleLeftOffset), ABS(cloudTopRightOffset)), ABS(cloudBottomRightOffset));
                    self->cloudMiddleLeftHorizontalConstraint.constant = -cloudWidth/2 - (maxOffset + cloudMiddleLeftOffset);
                    self->cloudMiddleRightHorizontalConstraint.constant = cloudWidth/2 - (maxOffset + cloudMiddleLeftOffset);
                    self->cloudTopRightHorizontalConstraint.constant = cloudWidth/2 + (maxOffset + cloudTopRightOffset);
                    self->cloudBottomRightHorizontalConstraint.constant = cloudWidth/2 + (maxOffset + cloudBottomRightOffset);
                    [self.view layoutIfNeeded];

                    [UIView animateWithDuration:0.25 * animationTimeStretchFactor delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                        disconnectedAndConnectedLayout();
                    } completion:nil];
                }
            }];
        } else {
            disconnectedAndConnectedLayout();
        }
    }
    else {
        // Disconnected

        removeAllCloudAnimations();

        disconnectedAndConnectedLayout();
    }

    previousState = s;
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
    NSString *upperCased = [s localizedUppercaseString];
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc]
      initWithString:upperCased];

    [mutableStr addAttribute:NSKernAttributeName
                       value:@1.1
                       range:NSMakeRange(0, mutableStr.length)];
    statusLabel.attributedText = mutableStr;
}

- (void)setupBottomBar {
    bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    bottomBar.backgroundColor = [UIColor clearColor];

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self action:@selector(onSubscriptionTap)];
    tapRecognizer.numberOfTapsRequired = 1;
    [bottomBar addGestureRecognizer:tapRecognizer];
    
    // Setup autolayout
    [NSLayoutConstraint activateConstraints:@[
      [bottomBar.topAnchor constraintEqualToAnchor:subscriptionsBar.topAnchor],
      [bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
      [bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
      [bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    bottomBarGradient = [CAGradientLayer layer];
    bottomBarGradient.frame = bottomBar.bounds; // frame reset in viewDidLayoutSubviews
    bottomBarGradient.colors = @[(id)UIColor.lightishBlue.CGColor,
                                 (id)UIColor.lightRoyalBlueTwo.CGColor];

    [bottomBar.layer insertSublayer:bottomBarGradient atIndex:0];
}

- (void)setupRegionSelectionButton {
    [regionSelectionButton addTarget:self action:@selector(onRegionSelectionButtonTap:) forControlEvents:UIControlEventTouchUpInside];

    [regionSelectionButton update];

    // Add constraints
    regionSelectionButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *idealBottomSpacing = [regionSelectionButton.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:-31.f];
    [idealBottomSpacing setPriority:999];

    [NSLayoutConstraint activateConstraints:@[
        idealBottomSpacing,
        [regionSelectionButton.heightAnchor constraintEqualToConstant:58.0],
        [regionSelectionButton.leadingAnchor constraintEqualToAnchor:viewWidthGuide.leadingAnchor],
        [regionSelectionButton.trailingAnchor constraintEqualToAnchor:settingsButton.leadingAnchor
                                                             constant:-10.f]
    ]];

}

- (void)setupVersionLabel {
    CGFloat padding = 10.0f;
    
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [versionLabel setTitle:[NSString stringWithFormat:@"V.%@",
                            [[NSBundle mainBundle]
                             objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]
                  forState:UIControlStateNormal];
    [versionLabel setTitleColor:UIColor.nepalGreyBlueColor forState:UIControlStateNormal];
    versionLabel.titleLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.titleLabel.font = [UIFont avenirNextBold:12.f];
    versionLabel.userInteractionEnabled = FALSE;
    versionLabel.contentEdgeInsets = UIEdgeInsetsMake(padding, padding, padding, padding);

# if DEBUG
    versionLabel.userInteractionEnabled = TRUE;
    [versionLabel addTarget:self
                     action:@selector(onVersionLabelTap:)
           forControlEvents:UIControlEventTouchUpInside];
#endif
    // Setup autolayout
    [NSLayoutConstraint activateConstraints:@[
      [versionLabel.trailingAnchor constraintEqualToAnchor:psiCashWidget.trailingAnchor
                                                  constant:padding + 15.f],
      [versionLabel.topAnchor constraintEqualToAnchor:psiphonTitle.topAnchor constant:-padding]
    ]];
}

- (void)setupSubscriptionsBar {
    [subscriptionsBar addTarget:self
                         action:@selector(onSubscriptionTap)
               forControlEvents:UIControlEventTouchUpInside];

    // Setup autolayout
    subscriptionsBar.translatesAutoresizingMaskIntoConstraints = FALSE;

    [NSLayoutConstraint activateConstraints:@[
      [subscriptionsBar.centerXAnchor constraintEqualToAnchor:bottomBar.centerXAnchor],
      [subscriptionsBar.centerYAnchor constraintEqualToAnchor:bottomBar.safeCenterYAnchor],
      [subscriptionsBar.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
      [subscriptionsBar.heightAnchor constraintGreaterThanOrEqualToConstant:100.0],
      [subscriptionsBar.heightAnchor constraintLessThanOrEqualToAnchor:self.view.safeHeightAnchor
                                                  multiplier:0.13],
    ]];

}

#pragma mark - FeedbackViewControllerDelegate methods and helpers

- (void)userSubmittedFeedback:(NSUInteger)selectedThumbIndex
                     comments:(NSString *)comments
                        email:(NSString *)email
            uploadDiagnostics:(BOOL)uploadDiagnostics {

    [feedbackManager userSubmittedFeedback:selectedThumbIndex
                                  comments:comments
                                     email:email
                         uploadDiagnostics:uploadDiagnostics];
}

- (void)userPressedURL:(NSURL *)URL {
    [[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:nil];
}

#pragma mark - PsiphonSettingsViewControllerDelegate methods and helpers

- (void)notifyPsiphonConnectionState {
    // Unused
}

- (void)reloadAndOpenSettings {
    if (appSettingsViewController != nil) {
        [appSettingsViewController dismissViewControllerAnimated:NO completion:^{
            [[RegionAdapter sharedInstance] reloadTitlesForNewLocalization];
            [[AppDelegate sharedAppDelegate] reloadMainViewControllerAndImmediatelyOpenSettings];
        }];
    }
}

- (void)settingsWillDismissWithForceReconnect:(BOOL)forceReconnect {
    if (forceReconnect) {
        [self persistSettingsToSharedUserDefaults];
        [SwiftDelegate.bridge restartVPNIfActive];
    }
}

- (void)persistSettingsToSharedUserDefaults {
    [self persistDisableTimeouts];
    [self persistSelectedRegion];
    [self persistUpstreamProxySettings];
}

- (void)persistDisableTimeouts {
    NSUserDefaults *containerUserDefaults = [NSUserDefaults standardUserDefaults];
    NSUserDefaults *sharedUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_IDENTIFIER];
    [sharedUserDefaults setObject:@([containerUserDefaults boolForKey:kDisableTimeouts]) forKey:kDisableTimeouts];
}

- (void)persistSelectedRegion {
    [[PsiphonConfigUserDefaults sharedInstance] setEgressRegion:[RegionAdapter.sharedInstance getSelectedRegion].code];
}

- (void)persistUpstreamProxySettings {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_IDENTIFIER];
    NSString *upstreamProxyUrl = [[UpstreamProxySettings sharedInstance] getUpstreamProxyUrl];
    [userDefaults setObject:upstreamProxyUrl forKey:PSIPHON_CONFIG_UPSTREAM_PROXY_URL];
    NSDictionary *upstreamProxyCustomHeaders = [[UpstreamProxySettings sharedInstance] getUpstreamProxyCustomHeaders];
    [userDefaults setObject:upstreamProxyCustomHeaders forKey:PSIPHON_CONFIG_UPSTREAM_PROXY_CUSTOM_HEADERS];
}

- (BOOL)shouldEnableSettingsLinks {
    return YES;
}

#pragma mark - Psiphon Settings

- (void)notice:(NSString *)noticeJSON {
    NSLog(@"Got notice %@", noticeJSON);
}

- (void)openSettingsMenu {
    appSettingsViewController = [[SettingsViewController alloc] init];
    appSettingsViewController.delegate = appSettingsViewController;
    appSettingsViewController.showCreditsFooter = NO;
    appSettingsViewController.showDoneButton = YES;
    appSettingsViewController.neverShowPrivacySettings = YES;
    appSettingsViewController.settingsDelegate = self;
    appSettingsViewController.preferencesSnapshot = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] copy];

    UINavigationController *navController = [[UINavigationController alloc]
      initWithRootViewController:appSettingsViewController];

    if (@available(iOS 13, *)) {
        // The default navigation controller in the iOS 13 SDK is not fullscreen and can be
        // dismissed by swiping it away.
        //
        // PsiphonSettingsViewController depends on being dismissed with the "done" button, which
        // is hooked into the InAppSettingsKit lifecycle. Swiping away the settings menu bypasses
        // this and results in the VPN not being restarted if: a new region was selected, the
        // disable timeouts settings was changed, etc. The solution is to force fullscreen
        // presentation until the settings menu can be refactored.
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
    }

    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - Subscription

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc] init];
    iapViewController.openedFromSettings = NO;
    UINavigationController *navController = [[UINavigationController alloc]
      initWithRootViewController:iapViewController];
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - PsiCash

#pragma mark - PsiCash UI

- (void)addPsiCashButtonTapped {
    UIViewController *psiCashViewController = [SwiftDelegate.bridge
                                               createPsiCashViewController:TabsAddPsiCash];
    [self presentViewController:psiCashViewController animated:YES completion:nil];
}

- (void)speedBoostButtonTapped {
    UIViewController *psiCashViewController = [SwiftDelegate.bridge
                                               createPsiCashViewController:TabsSpeedBoost];
    [self presentViewController:psiCashViewController animated:YES completion:nil];
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

- (void)setupNoConnectionBannerView {
    noConnectionBannerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [noConnectionBannerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [noConnectionBannerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [noConnectionBannerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [noConnectionBannerView.bottomAnchor constraintEqualToAnchor:psiphonTitle.bottomAnchor]
    ]];
    
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

    // Sets button action
    [psiCashWidget.addPsiCashButton addTarget:self action:@selector(addPsiCashButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [psiCashWidget.speedBoostButton addTarget:self action:@selector(speedBoostButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Makes balance view tappable
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self
                                             action:@selector(addPsiCashButtonTapped)];
    [psiCashWidget.balanceView addGestureRecognizer:tapRecognizer];
}

- (void)setPsiCashContentHidden:(BOOL)hidden {
    psiCashWidget.hidden = hidden;
    psiCashWidget.userInteractionEnabled = !hidden;

    // Show Psiphon large logo and hide Psiphon small logo when PsiCash is hidden.
    psiphonLargeLogo.hidden = !hidden;
    psiphonTitle.hidden = hidden;
}

#pragma mark - RegionAdapterDelegate protocol implementation

- (void)selectedRegionDisappearedThenSwitchedToBestPerformance {
    MainViewController *__weak weakSelf = self;
    dispatch_async_main(^{
        MainViewController *__strong strongSelf = weakSelf;
        [strongSelf->regionSelectionButton update];
    });
    [self persistSelectedRegion];
}

@end
