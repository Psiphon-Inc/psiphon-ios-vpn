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

PsiFeedbackLogType const MainViewControllerLogType = @"MainViewController";

#if DEBUG
NSTimeInterval const MaxAdLoadingTime = 1.f;
#else
NSTimeInterval const MaxAdLoadingTime = 10.f;
#endif

typedef NS_ENUM(NSInteger, VPNIntent) {
    VPNIntentStartPsiphonTunnelWithoutAds,
    VPNIntentStartPsiphonTunnelWithAds,
    VPNIntentStopVPN,
    VPNIntentNoInternetAlert,
};

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

              } else if (startStatus == VPNStartStopStatusFailedOtherReason) {

                  // Alert the user that the VPN failed to start, and that they should try again.
                  [UIAlertController presentSimpleAlertWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_FAIL_TITLE", nil, [NSBundle mainBundle], @"Unable to start", @"Alert dialog title indicating to the user that Psiphon was unable to start (MainViewController)")
                                                         message:NSLocalizedStringWithDefaultValue(@"VPN_START_FAIL_MESSAGE", nil, [NSBundle mainBundle], @"An error occurred while starting Psiphon. Please try again. If this problem persists, try reinstalling the Psiphon app.", @"Alert dialog message informing the user that an error occurred while starting Psiphon (Do not translate 'Psiphon'). The user should try again, and if the problem persists, they should try reinstalling the app.")
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

    // If MainViewController is asked to start VPN first, then initialize dependencies
    // only after starting the VPN. Otherwise, we initialize the dependencies immediately.
    {
        __block RACDisposable *startDisposable = [[[[RACSignal return:@(self.startVPNOnFirstLoad)]
          flattenMap:^RACSignal<RACUnit *> *(NSNumber *startVPNFirst) {

              if ([startVPNFirst boolValue]) {
                  return [[weakSelf startOrStopVPNSignalWithAd:FALSE]
                    mapReplace:RACUnit.defaultUnit];
              } else {
                  return [RACSignal return:RACUnit.defaultUnit];
              }
          }]
          doNext:^(RACUnit *x) {
              // Start AdManager lifecycle.
              // Important: dependencies might be initialized while the tunnel is connecting or
              // when there is no active internet connection.
              [[AdManager sharedInstance] initializeAdManager];
              [[AdManager sharedInstance] initializeRewardedVideos];
          }]
          subscribeError:^(NSError *error) {
              [weakSelf.compoundDisposable removeDisposable:startDisposable];
          }
          completed:^{
              [weakSelf.compoundDisposable removeDisposable:startDisposable];
          }];

        [self.compoundDisposable addDisposable:startDisposable];
    }

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

    // Subscribes to `AppDelegate.speedBoostExpiry` subject to update `psiCashWidget` with the
    // latest expiry time.
    {
        [self.compoundDisposable addDisposable:[AppObservables.shared.speedBoostExpiry
                                                subscribeNext:^(NSDate * _Nullable expiry) {
            MainViewController *__strong strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->psiCashWidget.speedBoostButton setExpiryTime:expiry];
            }
        }]];
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

    // adsLoadingSignal emits a value when untunnelled interstitial ad has loaded or
    // when MaxAdLoadingTime has passed.
    // If the device in not in untunneled state, this signal makes an emission and
    // then completes immediately, without checking the untunneled interstitial status.
    RACSignal *adsLoadingSignal = [[AppObservables.shared.vpnStatus
      flattenMap:^RACSignal *(NSNumber *statusObject) {

          VPNStatus s = (VPNStatus) [statusObject integerValue];
          BOOL needAdConsent = [MoPub sharedInstance].shouldShowConsentDialog;

          if (!needAdConsent && (s == VPNStatusDisconnected || s == VPNStatusInvalid)) {

              // Device is untunneled and ad consent is given or not needed,
              // we therefore wait for the ad to load.
              return [[[[AdManager sharedInstance].untunneledInterstitialLoadStatus
                filter:^BOOL(NSNumber *loadStatus) {
                    AdLoadStatus status = (AdLoadStatus) [loadStatus integerValue];
                    return status == AdLoadStatusDone;
                }]
                merge:[RACSignal timer:MaxAdLoadingTime]]
                take:1];

          } else {
              // Device in _not_ untunneled or we need to show the Ad consent modal screen,
              // wo we will emit RACUnit immediately since no ads will be loaded here.
              return [RACSignal return:RACUnit.defaultUnit];
          }
      }]
      take:1];

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
            return [adsLoadingSignal mapReplace:RACUnit.defaultUnit];
        }
    }];
}

// Emitted NSNumber is of type VPNIntent.
- (RACSignal<RACTwoTuple<NSNumber*, SwitchedVPNStartStopIntent*> *> *)startOrStopVPNSignalWithAd:(BOOL)showAd {
    MainViewController *__weak weakSelf = self;
    return [[[[RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {
        [[SwiftDelegate.bridge swithVPNStartStopIntent]
         then:^id _Nullable(SwitchedVPNStartStopIntent * newIntent) {
            if (newIntent == nil) {
                [NSException raise:@"nil found"
                            format:@"expected non-nil SwitchedVPNStartStopIntent value"];
            }
            
            VPNIntent vpnIntentValue;
            
            if (newIntent.intendToStart) {
                // If the new intent is to start the VPN, first checks for internet connectivity.
                // If there is internet connectivity, tunnel can be startet without ads
                // if the user is subscribed, if if there the VPN config is not installed.
                // Otherwise tunnel should be started after interstitial ad has been displayed.
                
                Reachability *reachability = [Reachability reachabilityForInternetConnection];
                if ([reachability currentReachabilityStatus] == NotReachable) {
                    vpnIntentValue = VPNIntentNoInternetAlert;
                } else {
                    if (newIntent.vpnConfigInstalled) {
                        if (newIntent.userSubscribed || !showAd) {
                            vpnIntentValue = VPNIntentStartPsiphonTunnelWithoutAds;
                        } else {
                            vpnIntentValue = VPNIntentStartPsiphonTunnelWithAds;
                        }
                    } else {
                        // VPN Config is not installed. Skip ads.
                        vpnIntentValue = VPNIntentStartPsiphonTunnelWithoutAds;
                    }
                }
            } else {
                // The new intent is to stop the VPN.
                vpnIntentValue = VPNIntentStopVPN;
            }
            
            [subscriber sendNext:[RACTwoTuple pack:@(vpnIntentValue) :newIntent]];
            [subscriber sendCompleted];
            return nil;
        }];
        
        return nil;
    }] flattenMap:^RACSignal<RACTwoTuple *> *(RACTwoTuple<NSNumber*, SwitchedVPNStartStopIntent*> *value) {
        VPNIntent vpnIntent = (VPNIntent)[value.first integerValue];
        if (vpnIntent == VPNIntentStartPsiphonTunnelWithAds) {
            // Start tunnel after ad presentation signal completes.
            // We always want to start the tunnel after the presentation signal
            // is completed, no matter if it presented an ad or it failed.
            return [[weakSelf.adManager presentInterstitialOnViewController:weakSelf]
                    then:^RACSignal * {
                return [RACSignal return:value];
            }];
        } else {
            return [RACSignal return:value];
        }
    }] doNext:^(RACTwoTuple<NSNumber*, SwitchedVPNStartStopIntent*> *value) {
        VPNIntent vpnIntent = (VPNIntent)[value.first integerValue];
        dispatch_async_main(^{
            [SwiftDelegate.bridge sendNewVPNIntent:value.second];

            if (vpnIntent == VPNIntentNoInternetAlert) {
                // TODO: Show the no internet alert.
            }
        });
    }] deliverOnMainThread];
}

#pragma mark - UI callbacks

- (void)onStartStopTap:(UIButton *)sender {
    MainViewController *__weak weakSelf = self;

    __block RACDisposable *disposable = [[self startOrStopVPNSignalWithAd:TRUE]
      subscribeError:^(NSError *error) {
        [weakSelf.compoundDisposable removeDisposable:disposable];
      }
      completed:^{
        [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
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
