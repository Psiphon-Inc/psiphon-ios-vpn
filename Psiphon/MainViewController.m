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
#import "DispatchUtils.h"
#import "FeedbackManager.h"
#import "IAPStoreHelper.h"
#import "IAPViewController.h"
#import "LaunchScreenViewController.h"
#import "Logging.h"
#import "DebugViewController.h"
#import "PsiFeedbackLogger.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonConfigUserDefaults.h"
#import "PsiphonDataSharedDB.h"
#import "PulsingHaloLayer.h"
#import "RegionSelectionViewController.h"
#import "SharedConstants.h"
#import "NEBridge.h"
#import "Notifier.h"
#import "UIAlertController+Delegate.h"
#import "UIImage+CountryFlag.h"
#import "UpstreamProxySettings.h"
#import "VPNManager.h"
#import "RACCompoundDisposable.h"
#import "RACTuple.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"
#import "RACSignal+Operations.h"
#import "RACSignal.h"
#import "RACUnit.h"
#import "NSNotificationCenter+RACSupport.h"
#import "Asserts.h"
#import "PrivacyPolicyViewController.h"
#import "UIColor+Additions.h"
#import "PsiCashRewardedVideoBar.h"
#import "PsiCashBalanceView.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostMeterView.h"
#import "PsiCashBalanceWithSpeedBoostMeter.h"
#import "UILabel+GetLabelHeight.h"
#import "StarView.h"

PsiFeedbackLogType const RewardedVideoLogType = @"RewardedVideo";

UserDefaultsKey const PrivacyPolicyAcceptedBoolKey = @"PrivacyPolicy.AcceptedBoolKey";
UserDefaultsKey const PsiCashHasBeenOnboardedBoolKey = @"PsiCash.HasBeenOnboarded";

static BOOL (^safeStringsEqual)(NSString *, NSString *) = ^BOOL(NSString *a, NSString *b) {
    return (([a length] == 0) && ([b length] == 0)) || ([a isEqualToString:b]);
};

@interface MainViewController ()

@property (nonatomic) RACCompoundDisposable *compoundDisposable;
@property (nonatomic) AdManager *adManager;
@property (nonatomic) VPNManager *vpnManager;

@end

@implementation MainViewController {
    
    PsiphonDataSharedDB *sharedDB;
    
    // UI elements
    UILabel *appTitleLabel;
    UILabel *appSubTitleLabel;
    UILabel *statusLabel;
    UILabel *versionLabel;
    UIButton *subscriptionButton;
    UILabel *regionButtonHeader;
    UIButton *regionButton;
    UIButton *startStopButton;
    PulsingHaloLayer *startStopButtonHalo;
    BOOL isStartStopButtonHaloOn;
    
    // UI Constraint
    NSLayoutConstraint *startButtonWidth;
    NSLayoutConstraint *startButtonHeight;
    NSLayoutConstraint *bottomBarTopConstraint;
    NSLayoutConstraint *subscriptionButtonTopConstraint;
    
    // UI Layer
    CAGradientLayer *backgroundGradient;
    
    // Settings
    PsiphonSettingsViewController *appSettingsViewController;
    UIButton *settingsButton;
    
    // Region Selection
    UINavigationController *regionSelectionNavController;
    UIView *bottomBar;
    NSString *selectedRegionSnapShot;
    
    FeedbackManager *feedbackManager;

    // PsiCash
    NSArray<StarView*> *stars;
    NSLayoutConstraint *psiCashViewHeight;
    NSLayoutConstraint *psiCashRewardedVideoBarHeight;
    PsiCashPurchaseAlertView *alertView;
    PsiCashClientModel *model;
    PsiCashBalanceWithSpeedBoostMeter *psiCashView;
    PsiCashRewardedVideoBar * psiCashRewardedVideoBar;
    RACDisposable *psiCashViewUpdates;

}

// Force portrait orientation
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown);
}

// No heavy initialization should be done here, since RootContainerController
// expects this method to return immediately.
// All such initialization could be deferred to viewDidLoad callback.
- (id)init {
    self = [super init];
    if (self) {
        
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
        
        _vpnManager = [VPNManager sharedInstance];
        
        _adManager = [AdManager sharedInstance];
        
        feedbackManager = [[FeedbackManager alloc] init];
        
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        
        [self persistSettingsToSharedUserDefaults];
        
        // Open Setting after change it
        self.openSettingImmediatelyOnViewDidAppear = NO;

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
    
    // Add any available regions from shared db to region adapter
    [self updateAvailableRegions];
    
    // Setting up the UI
    // calls them in the right order
    [self setBackgroundGradient];
    [self setNeedsStatusBarAppearanceUpdate];
    [self addSettingsButton];
    [self addRegionSelectionBar];
    [self addStartAndStopButton];
    [self addAppTitleLabel];
    [self addAppSubTitleLabel];
    [self addSubscriptionButton];
    [self addPsiCashView];
    [self addPsiCashRewardedVideoBar];
    [self addStatusLabel];
    [self addVersionLabel];
    [self setupLayoutGuides];
    
    if (([[UIDevice currentDevice].model hasPrefix:@"iPhone"] ||
         [[UIDevice currentDevice].model hasPrefix:@"iPod"]) &&
        (self.view.bounds.size.width > self.view.bounds.size.height)) {
        appTitleLabel.hidden = YES;
        appSubTitleLabel.hidden = YES;
    }
    
    __weak MainViewController *weakSelf = self;
    
    // Observe VPN status for updating UI state
    RACDisposable *tunnelStatusDisposable = [self.vpnManager.lastTunnelStatus
      subscribeNext:^(NSNumber *statusObject) {
          VPNStatus s = (VPNStatus) [statusObject integerValue];

          [weakSelf updateUIConnectionState:s];

          if (s == VPNStatusConnecting ||
              s == VPNStatusRestarting ||
              s == VPNStatusReasserting) {

              [weakSelf addPulsingHaloLayer];

          } else {
              [weakSelf removePulsingHaloLayer];
          }

          // Notify SettingsViewController that the state has changed.
          // Note that this constant is used PsiphonClientCommonLibrary, and cannot simply be replaced by a RACSignal.
          // TODO: replace this notification with the appropriate signal.
          [[NSNotificationCenter defaultCenter] postNotificationName:kPsiphonConnectionStateNotification object:nil];

      }];
    
    [self.compoundDisposable addDisposable:tunnelStatusDisposable];
    
    RACDisposable *vpnStartStatusDisposable = [[self.vpnManager.vpnStartStatus
      deliverOnMainThread]
      subscribeNext:^(NSNumber *statusObject) {
          VPNStartStatus startStatus = (VPNStartStatus) [statusObject integerValue];

          if (startStatus == VPNStartStatusStart) {
              [startStopButton setHighlighted:TRUE];
          } else {
              [startStopButton setHighlighted:FALSE];
          }

          if (startStatus == VPNStartStatusFailedUserPermissionDenied) {
              
              // Alert the user that their permission is required in order to install the VPN configuration.
              UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_PERMISSION_REQUIRED_TITLE", nil, [NSBundle mainBundle], @"Permission required", @"Alert dialog title indicating to the user that Psiphon needs their permission")
                                                                             message:NSLocalizedStringWithDefaultValue(@"VPN_START_PERMISSION_DENIED_MESSAGE", nil, [NSBundle mainBundle], @"Psiphon needs your permission to install a VPN profile in order to connect.\n\nPsiphon is committed to protecting the privacy of our users. You can review our privacy policy by tapping \"Privacy Policy\".", @"('Privacy Policy' should be the same translation as privacy policy button VPN_START_PRIVACY_POLICY_BUTTON), (Do not translate 'VPN profile'), (Do not translate 'Psiphon')")
                                                                      preferredStyle:UIAlertControllerStyleAlert];

              UIAlertAction *privacyPolicyAction = [UIAlertAction actionWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_PRIVACY_POLICY_BUTTON", nil, [NSBundle mainBundle], @"Privacy Policy", @"Button label taking user's to our Privacy Policy page")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    NSString *urlString = NSLocalizedStringWithDefaultValue(@"PRIVACY_POLICY_URL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"https://psiphon.ca/en/privacy.html", @"External link to the privacy policy page. Please update this with the correct language specific link (if available) e.g. https://psiphon.ca/fr/privacy.html for french.");
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString]
                       options:@{}
                       completionHandler:^(BOOL success) {
                        // Do nothing.
                    }];
                }];

              UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_PERMISSION_DISMISS_BUTTON", nil, [NSBundle mainBundle], @"Dismiss", @"Dismiss button title. Dismisses pop-up alert when the user clicks on the button")
                                                                      style:UIAlertActionStyleCancel
                                                                    handler:^(UIAlertAction *action) {
                                                                        // Do nothing.
                                                                    }];

              [alert addAction:privacyPolicyAction];
              [alert addAction:dismissAction];
              [alert presentFromTopController];

          } else if (startStatus == VPNStartStatusFailedOther) {

              // Alert the user that the VPN failed to start, and that they should try again.
              [UIAlertController presentSimpleAlertWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_FAIL_TITLE", nil, [NSBundle mainBundle], @"Unable to start", @"Alert dialog title indicating to the user that Psiphon was unable to start (MainViewController)")
                                                     message:NSLocalizedStringWithDefaultValue(@"VPN_START_FAIL_MESSAGE", nil, [NSBundle mainBundle], @"An error occurred while starting Psiphon. Please try again. If this problem persists, try reinstalling the Psiphon app.", @"Alert dialog message informing the user that an error occurred while starting Psiphon (Do not translate 'Psiphon'). The user should try again, and if the problem persists, they should try reinstalling the app.")
                                              preferredStyle:UIAlertControllerStyleAlert
                                                   okHandler:nil];
          }
      }];
    
    [self.compoundDisposable addDisposable:vpnStartStatusDisposable];


    // Subscribes to AppDelegate subscription signal.
    __block RACDisposable *disposable = [[AppDelegate sharedAppDelegate].subscriptionStatus
      subscribeNext:^(NSNumber *value) {
          UserSubscriptionStatus s = (UserSubscriptionStatus) [value integerValue];

          if (s == UserSubscriptionUnknown) {
              return;
          }

          subscriptionButton.hidden = (s == UserSubscriptionActive);
          subscriptionButtonTopConstraint.active = !subscriptionButton.hidden;
          bottomBarTopConstraint.active = subscriptionButton.hidden;

          BOOL showPsiCashUI = (s == UserSubscriptionInactive);
          [self setPsiCashContentHidden:!showPsiCashUI];

      } error:^(NSError *error) {
          [self.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [self.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

- (void)viewDidAppear:(BOOL)animated {
    LOG_DEBUG();
    [super viewDidAppear:animated];
    // Available regions may have changed in the background
    [self updateAvailableRegions];
    [self updateRegionButton];
    
    if (self.openSettingImmediatelyOnViewDidAppear) {
        [self openSettingsMenu];
        self.openSettingImmediatelyOnViewDidAppear = NO;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    backgroundGradient.frame = self.view.bounds;
    
    if (isStartStopButtonHaloOn && startStopButtonHalo != nil) {
        // Keep pulsing halo centered on the start/stop button
        startStopButtonHalo.position = startStopButton.center;
    }
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
    
    if (isStartStopButtonHaloOn && startStopButtonHalo != nil) {
        // The pulsing halo animation will complete when MainViewController's view disappears.
        // Subsequently, PulsingHaloLayer will remove itself from its superview (see PulsingHaloLayer.m).
        // PulsingHaloLayer will be re-added if needed when MainViewController's view re-appears.
        [self removePulsingHaloLayer];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

// Reload when rotate
- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {

    [self setStartButtonSizeConstraints:size];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (isStartStopButtonHaloOn && startStopButtonHalo) {
            startStopButtonHalo.hidden = YES;
        }
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (isStartStopButtonHaloOn && startStopButtonHalo) {
            startStopButtonHalo.hidden = NO;
        }
    }];
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

#pragma mark - UI callbacks

- (void)onStartStopTap:(UIButton *)sender {

    __weak MainViewController *weakSelf = self;

    // privacyPolicyDismissed is a cold terminating signal that emits @TRUE if the PP was accepted,
    // otherwise emits @FALSE.
    RACSignal<NSNumber *> *privacyPolicyDismissed = [[RACSignal return:
                   @([NSUserDefaults.standardUserDefaults boolForKey:PrivacyPolicyAcceptedBoolKey])]
      flattenMap:^RACSignal<RACUnit *> *(NSNumber *alreadyAccepted) {

        if ([alreadyAccepted boolValue]) {
            return [RACSignal return:alreadyAccepted];
        } else {

            PrivacyPolicyViewController *c = [[PrivacyPolicyViewController alloc] init];
            [self presentViewController:c animated:TRUE completion:nil];

            return [[[[[NSNotificationCenter defaultCenter]
              rac_addObserverForName:PrivacyPolicyDismissedNotification
                              object:nil]
              take:1]
              map:^NSNumber *(NSNotification *notification) {
                  return notification.userInfo[PrivacyPolicyAcceptedNotificationBoolKey];
              }]
              doNext:^(NSNumber *accepted) {
                  // Update user defaults value.
                  [NSUserDefaults.standardUserDefaults setBool:[accepted boolValue]
                                                        forKey:PrivacyPolicyAcceptedBoolKey];
              }];
        }
    }];


    NSString * const CommandNoInternetAlert = @"NoInternetAlert";
    NSString * const CommandStartTunnel = @"StartTunnel";
    NSString * const CommandStopVPN = @"StopVPN";

    // signal emits a single two tuple (isVPNActive, connectOnDemandEnabled).
    __block RACDisposable *disposable = [[[[privacyPolicyDismissed
      flattenMap:^RACSignal<RACTwoTuple <NSNumber *, NSNumber *> *> *(NSNumber *accepted) {
          // If the user has accepted the privacy policy continue with starting the VPN,
          // otherwise terminate the subscription.
          if ([accepted boolValue]) {
              return [weakSelf.vpnManager isVPNActive];
          } else {
              return [RACSignal empty];
          }
      }]
      flattenMap:^RACSignal<NSString *> *(RACTwoTuple<NSNumber *, NSNumber *> *value) {
          BOOL vpnActive = [value.first boolValue];
          BOOL isZombie = (VPNStatusZombie == (VPNStatus)[value.second integerValue]);

          // Emits command to stop VPN if it has already started or is in zombie mode.
          // Otherwise, it checks for internet connectivity and emits
          // one of CommandNoInternetAlert or CommandStartTunnel.
          if (vpnActive || isZombie) {
              return [RACSignal return:CommandStopVPN];

          } else {
              // Alerts the user if there is no internet connection.
              Reachability *reachability = [Reachability reachabilityForInternetConnection];
              if ([reachability currentReachabilityStatus] == NotReachable) {
                  return [RACSignal return:CommandNoInternetAlert];

              } else {

                  // Returned signal checks whether or not VPN configuration is already installed.
                  // Skips presenting ads if the VPN configuration is not installed.
                  return [[weakSelf.vpnManager vpnConfigurationInstalled]
                    flattenMap:^RACSignal *(NSNumber *value) {
                        BOOL vpnInstalled = [value boolValue];

                        if (!vpnInstalled) {
                            return [RACSignal return:CommandStartTunnel];
                        } else {
                            // Start tunnel after ad presentation signal completes.
                            // We always want to start the tunnel after the presentation signal is completed,
                            // no matter if it presented an ad or it failed.
                            return [[weakSelf.adManager presentInterstitialOnViewController:weakSelf]
                              then:^RACSignal * {
                                  return [RACSignal return:CommandStartTunnel];
                              }];
                        }
                    }];
              }
          }

      }]
      deliverOnMainThread]
      subscribeNext:^(NSString *command) {

        if ([CommandStartTunnel isEqualToString:command]) {
            [weakSelf.vpnManager startTunnel];

        } else if ([CommandStopVPN isEqualToString:command]) {
            [weakSelf.vpnManager stopVPN];

        } else if ([CommandNoInternetAlert isEqualToString:command]) {
            [[AppDelegate sharedAppDelegate] displayAlertNoInternet:nil];
        }

    } error:^(NSError *error) {
        [weakSelf.compoundDisposable removeDisposable:disposable];
    } completed:^{
        [weakSelf removePulsingHaloLayer];
        [weakSelf.compoundDisposable removeDisposable:disposable];
    }];
    
    [self.compoundDisposable addDisposable:disposable];
}

- (void)onSettingsButtonTap:(UIButton *)sender {
    [self openSettingsMenu];
}

- (void)onRegionButtonTap:(UIButton *)sender {
    [self openRegionSelection];
}

- (void)onSubscriptionTap {
    [self openIAPViewController];
}

#if DEBUG
- (void)onVersionLabelTap:(UILabel *)sender {
    DebugViewController *viewController = [[DebugViewController alloc] initWithCoder:nil];
    [self presentViewController:viewController animated:YES completion:nil];
}
#endif

# pragma mark - UI helper functions

- (NSString *)getVPNStatusDescription:(VPNStatus)status {
    switch(status) {
        case VPNStatusDisconnected: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_DISCONNECTED", nil, [NSBundle mainBundle], @"Disconnected", @"Status when the VPN is not connected to a Psiphon server, not trying to connect, and not in an error state");
        case VPNStatusInvalid: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_INVALID", nil, [NSBundle mainBundle], @"Disconnected", @"Status when the VPN is in an invalid state. For example, if the user doesn't give permission for the VPN configuration to be installed, and therefore the Psiphon VPN can't even try to connect.");
        case VPNStatusConnected: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_CONNECTED", nil, [NSBundle mainBundle], @"Connected", @"Status when the VPN is connected to a Psiphon server");
        case VPNStatusConnecting: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_CONNECTING", nil, [NSBundle mainBundle], @"Connecting", @"Status when the VPN is connecting; that is, trying to connect to a Psiphon server");
        case VPNStatusDisconnecting: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_DISCONNECTING", nil, [NSBundle mainBundle], @"Disconnecting", @"Status when the VPN is disconnecting. Sometimes going from connected to disconnected can take some time, and this is that state.");
        case VPNStatusReasserting: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_RECONNECTING", nil, [NSBundle mainBundle], @"Reconnecting", @"Status when the VPN was connected to a Psiphon server, got disconnected unexpectedly, and is currently trying to reconnect");
        case VPNStatusRestarting: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_RESTARTING", nil, [NSBundle mainBundle], @"Restarting", @"Status when the VPN is restarting.");
        case VPNStatusZombie: return @"...";
    }
    [PsiFeedbackLogger error:@"MainViewController unhandled VPNStatus (%ld)", status];
    return nil;
}

- (void)setBackgroundGradient {
    backgroundGradient = [CAGradientLayer layer];
    
    backgroundGradient.colors = @[(id)[UIColor colorWithRed:0.57 green:0.62 blue:0.77 alpha:1.0].CGColor,
                                  (id)[UIColor colorWithRed:0.24 green:0.26 blue:0.33 alpha:1.0].CGColor];
    
    [self.view.layer insertSublayer:backgroundGradient atIndex:0];
}

- (void)addPulsingHaloLayer {
    // Don't add multiple layers
    if (isStartStopButtonHaloOn) {
        return;
    }
    isStartStopButtonHaloOn = TRUE;
    
    CGFloat radius = (CGFloat) (MIN(self.view.frame.size.width, self.view.frame.size.height) / 2.5);
    
    startStopButtonHalo = [PulsingHaloLayer layer];
    startStopButtonHalo.position = startStopButton.center;
    startStopButtonHalo.radius = radius;
    startStopButtonHalo.backgroundColor =
    [UIColor colorWithRed:0.44 green:0.51 blue:0.58 alpha:1.0].CGColor;
    startStopButtonHalo.haloLayerNumber = 3;
    
    [self.view.layer insertSublayer:startStopButtonHalo below:startStopButton.layer];
    
    [startStopButtonHalo start];
}

- (void)removePulsingHaloLayer {
    [startStopButtonHalo stop];
    isStartStopButtonHaloOn = FALSE;
}

- (BOOL)isRightToLeft {
    return ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);
}

- (void)addAppTitleLabel {
    appTitleLabel = [[UILabel alloc] init];
    appTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appTitleLabel.text = @"PSIPHON";
    appTitleLabel.textAlignment = NSTextAlignmentCenter;
    appTitleLabel.textColor = [UIColor whiteColor];
    appTitleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.06];
    appTitleLabel.shadowOffset = CGSizeMake(1.f, 1.f);

    CGFloat narrowestWidth = self.view.frame.size.width;
    if (self.view.frame.size.height < self.view.frame.size.width) {
        narrowestWidth = self.view.frame.size.height;
    }
    appTitleLabel.font = [UIFont fontWithName:@"Bourbon-Oblique" size:narrowestWidth * 0.10625f];
    if ([PsiphonClientCommonLibraryHelpers unsupportedCharactersForFont:appTitleLabel.font.fontName
                                                             withString:appTitleLabel.text]) {
        appTitleLabel.font = [UIFont systemFontOfSize:narrowestWidth * 0.075f];
    }

    [self.view addSubview:appTitleLabel];

    // Setup autolayout
    CGFloat labelHeight = [appTitleLabel getLabelHeight];
    [appTitleLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;
    [appTitleLabel.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor].active = YES;
    [appTitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)addAppSubTitleLabel {
    appSubTitleLabel = [[UILabel alloc] init];
    appSubTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appSubTitleLabel.text = NSLocalizedStringWithDefaultValue(@"APP_SUB_TITLE_MAIN_VIEW", nil, [NSBundle mainBundle], @"BEYOND BORDERS", @"Text for app subtitle on main view.");
    appSubTitleLabel.textAlignment = NSTextAlignmentCenter;
    appSubTitleLabel.textColor = [UIColor whiteColor];
    appSubTitleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.06];
    appSubTitleLabel.shadowOffset = CGSizeMake(1.f, 1.f);
    CGFloat narrowestWidth = self.view.frame.size.width;
    if (self.view.frame.size.height < self.view.frame.size.width) {
        narrowestWidth = self.view.frame.size.height;
    }
    appSubTitleLabel.font = [UIFont fontWithName:@"Bourbon-Oblique" size:narrowestWidth * 0.10625f/2.0f];
    if ([PsiphonClientCommonLibraryHelpers unsupportedCharactersForFont:appSubTitleLabel.font.fontName
                                                             withString:appSubTitleLabel.text]) {
        appSubTitleLabel.font = [UIFont systemFontOfSize:narrowestWidth * 0.075f/2.0f];
    }

    [self.view addSubview:appSubTitleLabel];

    // Setup autolayout
    CGFloat labelHeight = [appSubTitleLabel getLabelHeight];
    [appSubTitleLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;
    [appSubTitleLabel.topAnchor constraintEqualToAnchor:appTitleLabel.bottomAnchor].active = YES;
    [appSubTitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)addSettingsButton {
    settingsButton = [[UIButton alloc] init];
    UIImage *gearTemplate = [[UIImage imageNamed:@"settings"]
      imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [settingsButton setImage:gearTemplate forState:UIControlStateNormal];
    [settingsButton setTintColor:[UIColor whiteColor]];
    [self.view addSubview:settingsButton];

    // Setup autolayout
    [settingsButton.centerYAnchor
      constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:gearTemplate.size.height/2 + 8.f].active = YES;
    [settingsButton.centerXAnchor
      constraintEqualToAnchor:self.view.trailingAnchor constant:-gearTemplate.size.width/2 - 15.f].active = YES;
    [settingsButton.widthAnchor constraintEqualToConstant:80].active = YES;
    [settingsButton.heightAnchor constraintEqualToAnchor:settingsButton.widthAnchor].active = YES;

    [settingsButton addTarget:self action:@selector(onSettingsButtonTap:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)updateUIConnectionState:(VPNStatus)s {
    
    [startStopButton setHighlighted:FALSE];
    
    if ([VPNManager mapIsVPNActive:s] && s != VPNStatusConnected) {
        UIImage *connectingButtonImage = [UIImage imageNamed:@"ConnectingButton"];
        
        [startStopButton setImage:connectingButtonImage forState:UIControlStateNormal];
    }
    else if (s == VPNStatusConnected) {
        UIImage *stopButtonImage = [UIImage imageNamed:@"StopButton"];
        [startStopButton setImage:stopButtonImage forState:UIControlStateNormal];
    }
    else {
        UIImage *startButtonImage = [UIImage imageNamed:@"StartButton"];
        [startStopButton setImage:startButtonImage forState:UIControlStateNormal];
    }
    
    statusLabel.text = [self getVPNStatusDescription:s];
}

- (void)addStartAndStopButton {
    startStopButton = [UIButton buttonWithType:UIButtonTypeCustom];
    startStopButton.translatesAutoresizingMaskIntoConstraints = NO;
    startStopButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    startStopButton.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
    [startStopButton addTarget:self action:@selector(onStartStopTap:) forControlEvents:UIControlEventTouchUpInside];
    
    // Shadow and Radius
    startStopButton.layer.shadowOffset = CGSizeMake(0, 6.0f);
    startStopButton.layer.shadowOpacity = 0.18f;
    startStopButton.layer.shadowRadius = 0.0f;
    startStopButton.layer.masksToBounds = NO;
    
    [self.view addSubview:startStopButton];
    
    // Setup autolayout
    [startStopButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;

    [self setStartButtonSizeConstraints:self.view.bounds.size];
}

- (void)setStartButtonSizeConstraints:(CGSize)size {
    if (startButtonWidth) {
        startButtonWidth.active = NO;
    }

    if (startButtonHeight) {
        startButtonHeight.active = NO;
    }

    startButtonWidth = [startStopButton.widthAnchor constraintEqualToConstant:MIN(size.width, size.height)*0.4];
    startButtonHeight = [startStopButton.heightAnchor constraintEqualToAnchor:startStopButton.widthAnchor];

    startButtonWidth.active = YES;
    startButtonHeight.active = YES;
}

- (void)addStatusLabel {
    statusLabel = [[UILabel alloc] init];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.adjustsFontSizeToFitWidth = YES;
    statusLabel.text = [self getVPNStatusDescription:VPNStatusInvalid];
    statusLabel.textAlignment = NSTextAlignmentCenter;
    statusLabel.textColor = [UIColor whiteColor];
    statusLabel.font = [UIFont boldSystemFontOfSize:18.f];
    statusLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.06];
    statusLabel.shadowOffset = CGSizeMake(1.f, 1.f);
    [self.view addSubview:statusLabel];
    
    // Setup autolayout
    CGFloat labelHeight = [statusLabel getLabelHeight];
    [statusLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;
    [statusLabel.topAnchor constraintGreaterThanOrEqualToAnchor:startStopButton.bottomAnchor constant:1].active = YES;
    [statusLabel.topAnchor constraintLessThanOrEqualToAnchor:startStopButton.bottomAnchor constant:5].active = YES;
    [statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)addRegionSelectionBar {
    [self addBottomBar];
    [self addRegionButton];
}

- (void)addBottomBar {
    bottomBar = [[UIView alloc] init];
    bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    bottomBar.backgroundColor = [UIColor whiteColor];

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self action:@selector(onRegionButtonTap:)];
    tapRecognizer.numberOfTapsRequired = 1;
    [bottomBar addGestureRecognizer:tapRecognizer];

    [self.view addSubview:bottomBar];
    
    // Setup autolayout
    [bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
}

- (void)addRegionButton {
    // Add text above region button first
    regionButtonHeader = [[UILabel alloc] init];
    regionButtonHeader.translatesAutoresizingMaskIntoConstraints = NO;
    regionButtonHeader.text = NSLocalizedStringWithDefaultValue(@"CONNECT_VIA", nil, [NSBundle mainBundle], @"Connect via", @"Text above change region button that allows user to select their desired server region");
    regionButtonHeader.adjustsFontSizeToFitWidth = YES;
    regionButtonHeader.font = [UIFont systemFontOfSize:14];
    regionButtonHeader.textColor = [UIColor colorWithRed:0.00 green:0.00 blue:0.00 alpha:.37f];
    [bottomBar addSubview:regionButtonHeader];
    
    // Restrict label's height to the actual size
    CGFloat labelHeight = [regionButtonHeader getLabelHeight];
    NSLayoutConstraint *labelHeightConstraint = [regionButtonHeader.heightAnchor constraintEqualToConstant:labelHeight];
    [labelHeightConstraint setPriority:999];
    [regionButtonHeader addConstraint:labelHeightConstraint];
    
    // Now the button
    regionButton = [[UIButton alloc] init];
    regionButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    CGFloat buttonHeight = 45;
    [regionButton setTitleColor:[UIColor colorWithWhite:0 alpha:.8] forState:UIControlStateNormal];
    [regionButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateHighlighted];
    regionButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightLight];
    regionButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
    CGFloat spacing = 10; // the amount of spacing to appear between image and title
    regionButton.titleEdgeInsets = UIEdgeInsetsMake(0, spacing, 0, spacing);
    [regionButton addTarget:self action:@selector(onRegionButtonTap:) forControlEvents:UIControlEventTouchUpInside];

    // Set button height
    [regionButton.heightAnchor constraintEqualToConstant:buttonHeight].active = YES;
    [bottomBar addSubview:regionButton];

    [self updateRegionButton];

    // Add constraints
    [regionButtonHeader.topAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:7].active = YES;
    [regionButtonHeader.centerXAnchor constraintEqualToAnchor:bottomBar.centerXAnchor].active = YES;
    [regionButton.topAnchor constraintEqualToAnchor:regionButtonHeader.bottomAnchor constant:5].active = YES;
    if (@available(iOS 11.0, *)) {
        [regionButton.bottomAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.bottomAnchor constant:-7].active = TRUE;
    } else {
        [regionButton.bottomAnchor constraintEqualToAnchor:bottomBar.bottomAnchor constant:-7].active = YES;
    }
    [regionButton.titleLabel.centerXAnchor constraintEqualToAnchor:regionButtonHeader.centerXAnchor].active = YES;
    [regionButton.widthAnchor constraintEqualToAnchor:bottomBar.widthAnchor multiplier:.7f].active = YES;

    // Add up arrow indicator
    UIImage *arrowImage = [UIImage imageNamed:@"UpArrow"];
    UIImageView *upArrow = [[UIImageView alloc] initWithImage:arrowImage];
    upArrow.contentMode = UIViewContentModeScaleAspectFit;

    [bottomBar addSubview:upArrow];
    upArrow.translatesAutoresizingMaskIntoConstraints = NO;
    [upArrow.leftAnchor constraintEqualToAnchor:regionButton.titleLabel.rightAnchor constant:spacing].active = YES;
    [upArrow.centerYAnchor constraintEqualToAnchor:regionButton.centerYAnchor].active = YES;
    [upArrow.widthAnchor constraintEqualToConstant:15].active = YES;
    [upArrow.heightAnchor constraintEqualToAnchor:upArrow.widthAnchor].active = YES;
}

- (void)addVersionLabel {
    versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.text = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"APP_VERSION", nil, [NSBundle mainBundle], @"v.%@", @"Text showing the app version. The '%@' placeholder is the version number. So it will look like 'v.2'."),[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    versionLabel.userInteractionEnabled = YES;
    versionLabel.textColor = [UIColor whiteColor];
    versionLabel.font = [versionLabel.font fontWithSize:13];

#if DEBUG
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self action:@selector(onVersionLabelTap:)];
    tapRecognizer.numberOfTapsRequired = 1;
    [versionLabel addGestureRecognizer:tapRecognizer];
#endif

    [self.view addSubview:versionLabel];

    // Setup autolayout
    [versionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12].active = YES;
    [versionLabel.centerYAnchor constraintEqualToAnchor:settingsButton.centerYAnchor].active = YES;
    [versionLabel.heightAnchor constraintEqualToConstant:50].active = YES;
}

- (void)addSubscriptionButton {
    subscriptionButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    subscriptionButton.layer.cornerRadius = 20;
    subscriptionButton.clipsToBounds = YES;
    [subscriptionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    subscriptionButton.titleLabel.font = [UIFont boldSystemFontOfSize:subscriptionButton.titleLabel.font.pointSize];
    subscriptionButton.backgroundColor = [UIColor colorWithRed:0.47 green:0.38 blue:1.00 alpha:1.0];
    
    subscriptionButton.contentEdgeInsets = UIEdgeInsetsMake(10.0f, 30.0f, 10.0f, 30.0f);
    
    NSString *subscriptionButtonTitle = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_BUTTON_TITLE",
                                                                          nil,
                                                                          [NSBundle mainBundle],
                                                                          @"Go premium now!",
                                                                          @"Text for button that opens paid subscriptions manager UI. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”.");
    [subscriptionButton setTitle:subscriptionButtonTitle forState:UIControlStateNormal];
    [subscriptionButton addTarget:self
                           action:@selector(onSubscriptionTap)
                 forControlEvents:UIControlEventTouchUpInside];
    subscriptionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:subscriptionButton];
    
    // Setup autolayout
    [subscriptionButton.heightAnchor constraintEqualToConstant:40].active = YES;
    [subscriptionButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    NSLayoutConstraint *idealBottomSpacing =
      [subscriptionButton.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:-10.f];
    [idealBottomSpacing setPriority:999];
    idealBottomSpacing.active = YES;
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
            [[AppDelegate sharedAppDelegate] reloadMainViewController];
        }];
    }
}

- (void)settingsWillDismissWithForceReconnect:(BOOL)forceReconnect {
    if (forceReconnect) {
        [self persistSettingsToSharedUserDefaults];
        [self.vpnManager restartVPNIfActive];
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
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - Region Selection

- (void)openRegionSelection {
    selectedRegionSnapShot = [[RegionAdapter sharedInstance] getSelectedRegion].code;
    RegionSelectionViewController *regionSelectionViewController = [[RegionSelectionViewController alloc] init];
    regionSelectionNavController = [[UINavigationController alloc]
      initWithRootViewController:regionSelectionViewController];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"DONE_ACTION", nil, [NSBundle mainBundle], @"Done", @"Title of the button that dismisses region selection dialog")
                                                                   style:UIBarButtonItemStyleDone target:self
                                                                  action:@selector(regionSelectionDidEnd)];
    regionSelectionViewController.navigationItem.rightBarButtonItem = doneButton;
    
    [self presentViewController:regionSelectionNavController animated:YES completion:nil];
}

- (void)regionSelectionDidEnd {
    NSString *selectedRegion = [[RegionAdapter sharedInstance] getSelectedRegion].code;
    if (!safeStringsEqual(selectedRegion, selectedRegionSnapShot)) {
        [self persistSelectedRegion];
        [self updateRegionButton];
        [self.vpnManager restartVPNIfActive];
    }
    [regionSelectionNavController dismissViewControllerAnimated:YES completion:nil];
    regionSelectionNavController = nil;
}

- (void)updateAvailableRegions {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSString *> *regions = [sharedDB emittedEgressRegions];

        if (regions == nil) {
            regions = [sharedDB embeddedEgressRegions];
        }

#if DEBUG
        if ([AppInfo runningUITest]) {
            // fake the availability of all regions in the UI for automated screenshots
            NSMutableArray *faked_regions = [[NSMutableArray alloc] init];
            for (Region *region in [[RegionAdapter sharedInstance] getRegions]) {
                [faked_regions addObject:region.code];
            }
            regions = faked_regions;
        }
#endif
        [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
    });
}

- (void)updateRegionButton {
    Region *selectedRegion = [[RegionAdapter sharedInstance] getSelectedRegion];
    UIImage *flag = [[PsiphonClientCommonLibraryHelpers imageFromCommonLibraryNamed:selectedRegion.flagResourceId]
      countryFlag];
    [regionButton setImage:flag forState:UIControlStateNormal];
    
    NSString *regionText = [[RegionAdapter sharedInstance] getLocalizedRegionTitle:selectedRegion.code];
    [regionButton setTitle:regionText forState:UIControlStateNormal];
}

- (void)setupLayoutGuides {
    // setup layout equal distribution
    UILayoutGuide *topSpacerGuide = [UILayoutGuide new];
    UILayoutGuide *bottomSpacerGuide = [UILayoutGuide new];
    
    [self.view addLayoutGuide:topSpacerGuide];
    [self.view addLayoutGuide:bottomSpacerGuide];
    
    [topSpacerGuide.heightAnchor constraintGreaterThanOrEqualToConstant:.1].active = YES;
    [bottomSpacerGuide.heightAnchor constraintEqualToAnchor:topSpacerGuide.heightAnchor].active = YES;
    [topSpacerGuide.topAnchor constraintEqualToAnchor:psiCashView.bottomAnchor].active = YES;
    [topSpacerGuide.bottomAnchor constraintEqualToAnchor:startStopButton.topAnchor].active = YES;
    [bottomSpacerGuide.topAnchor constraintEqualToAnchor:statusLabel.bottomAnchor].active = YES;
    
    bottomBarTopConstraint = [bottomSpacerGuide.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor];
    subscriptionButtonTopConstraint = [bottomSpacerGuide.bottomAnchor
      constraintEqualToAnchor:subscriptionButton.topAnchor];
}

#pragma mark - Subscription

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = NO;
    UINavigationController *navController = [[UINavigationController alloc]
      initWithRootViewController:iapViewController];
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - PsiCash

#pragma mark - PsiCash UI actions

/**
 * Buy max num hours of Speed Boost that the user can afford if possible
 */
- (void)instantMaxSpeedBoostPurchase {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    if (![userDefaults boolForKey:PsiCashHasBeenOnboardedBoolKey]) {
        PsiCashOnboardingViewController *onboarding = [[PsiCashOnboardingViewController alloc] init];
        onboarding.delegate = self;
        [self presentViewController:onboarding animated:NO completion:nil];
        return;
    }

    // Checks the latest tunnel status before going ahead with the purchase request.
     __block RACDisposable *disposable = [[[VPNManager sharedInstance].lastTunnelStatus
       take:1]
       subscribeNext:^(NSNumber *value) {
           VPNStatus s = (VPNStatus) [value integerValue];

           if (s == VPNStatusConnected || s == VPNStatusDisconnected || s == VPNStatusInvalid) {
               // Device is either tunneled or untunneled, we can go ahead with the purchase request.
               PsiCashSpeedBoostProductSKU *purchase = [model maxSpeedBoostPurchaseEarned];
               if (![model hasPendingPurchase] && ![model hasActiveSpeedBoostPurchase] && purchase != nil) {
                   [PsiCashClient.sharedInstance purchaseSpeedBoostProduct:purchase];
               } else {
                   [self showPsiCashAlertView];
               }
           } else {
               // Device is in a connecting or disconnecting state, we shouldn't do any purchase requests.
               // Informs the user through an alert.
               NSString *alertBody = NSLocalizedStringWithDefaultValue(@"PSICASH_CONNECTED_OR_DISCONNECTED",
                 nil,
                 [NSBundle mainBundle],
                 @"Speed Boost purchase unavailable while Psiphon is connecting.",
                 @"Alert message indicating to the user that they can't purchase Speed Boost while the app is connecting."
                 " Do not translate 'Psiphon'.");

               [UIAlertController presentSimpleAlertWithTitle:@"PsiCash"  // The word PsiCash is not translated.
                                                      message:alertBody
                                               preferredStyle:UIAlertControllerStyleAlert
                                                    okHandler:nil];
           }
       }
       completed:^{
           [self.compoundDisposable removeDisposable:disposable];
       }];

    [self.compoundDisposable addDisposable:disposable];
}

#pragma mark - PsiCash UI

- (void)addPsiCashView {
    psiCashView = [[PsiCashBalanceWithSpeedBoostMeter alloc] init];
    psiCashView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:psiCashView];

    UITapGestureRecognizer *psiCashViewTap = [[UITapGestureRecognizer alloc]
                                                  initWithTarget:self action:@selector(instantMaxSpeedBoostPurchase)];

    psiCashViewTap.numberOfTapsRequired = 1;
    [psiCashView addGestureRecognizer:psiCashViewTap];

    [psiCashView.centerXAnchor constraintEqualToAnchor:appSubTitleLabel.centerXAnchor].active = YES;
    [psiCashView.topAnchor constraintGreaterThanOrEqualToAnchor:appSubTitleLabel.bottomAnchor].active = YES;
    NSLayoutConstraint *topSpacing = [psiCashView.topAnchor constraintEqualToAnchor:appSubTitleLabel.bottomAnchor
                                                                           constant:30.f];
    [topSpacing setPriority:999];
    topSpacing.active = YES;

    CGFloat psiCashViewMaxWidth = 400;
    CGFloat psiCashViewToParentViewWidthRatio = 0.95;
    if (self.view.frame.size.width * psiCashViewToParentViewWidthRatio > psiCashViewMaxWidth) {
        [psiCashView.widthAnchor constraintEqualToConstant:psiCashViewMaxWidth].active = YES;
    } else {
        [psiCashView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.95].active = YES;
    }
    psiCashViewHeight = [psiCashView.heightAnchor constraintEqualToConstant:100];
    psiCashViewHeight.active = YES;

    // Highlight PsiCashView
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if (![userDefaults boolForKey:PsiCashHasBeenOnboardedBoolKey]) {
        [self highlightPsiCashViewWithStars];
    }

    __weak MainViewController *weakSelf = self;

    [psiCashViewUpdates dispose];

    psiCashViewUpdates = [[PsiCashClient.sharedInstance.clientModelSignal deliverOnMainThread]
      subscribeNext:^(PsiCashClientModel *newClientModel) {
        __strong MainViewController *strongSelf = weakSelf;
        if (strongSelf != nil) {

            BOOL stateChanged = [model hasActiveSpeedBoostPurchase] ^ [newClientModel hasActiveSpeedBoostPurchase]
              || [model hasPendingPurchase] ^ [newClientModel hasPendingPurchase];

            NSComparisonResult balanceChange = [model.balance compare:newClientModel.balance];
            if (balanceChange != NSOrderedSame) {
                NSNumber *balanceChange =
                  [NSNumber numberWithDouble:newClientModel.balance.doubleValue - model.balance.doubleValue];
                [PsiCashBalanceWithSpeedBoostMeter animateBalanceChangeOf:balanceChange
                                                          withPsiCashView:psiCashView
                                                             inParentView:self.view];
            }

            model = newClientModel;

            if (stateChanged && alertView != nil) {
                [self showPsiCashAlertView];
            }

            [psiCashView bindWithModel:model];
        }
    }];

#if DEBUG
    if ([AppInfo runningUITest]) {
        [psiCashViewUpdates dispose];
        [self onboardingEnded];

        PsiCashSpeedBoostProductSKU *sku =
          [PsiCashSpeedBoostProductSKU skuWitDistinguisher:@"1h"
                                                 withHours:[NSNumber numberWithInteger:1]
                                                  andPrice:[NSNumber numberWithDouble:100e9]];

        PsiCashClientModel *m = [PsiCashClientModel
            clientModelWithAuthPackage:[[PsiCashAuthPackage alloc]
                                         initWithValidTokens:@[@"indicator", @"earner", @"spender"]]
                            andBalance:[NSNumber numberWithDouble:70e9]
                  andSpeedBoostProduct:[PsiCashSpeedBoostProduct productWithSKUs:@[sku]]
                   andPendingPurchases:nil
           andActiveSpeedBoostPurchase:nil
                     andRefreshPending:NO];

        [psiCashView bindWithModel:m];
    }
#endif
}

- (void)highlightPsiCashViewWithStars {
    StarView *star1 = [[StarView alloc] init];
    [self.view addSubview:star1];

    star1.translatesAutoresizingMaskIntoConstraints = NO;
    [star1.centerXAnchor constraintEqualToAnchor:psiCashView.balance.leadingAnchor constant:5].active = YES;
    [star1.centerYAnchor constraintEqualToAnchor:psiCashView.meter.bottomAnchor constant:-2].active = YES;
    [star1.widthAnchor constraintEqualToConstant:20].active = YES;
    [star1.heightAnchor constraintEqualToAnchor:star1.widthAnchor].active = YES;

    StarView *star2 = [[StarView alloc] init];
    [self.view addSubview:star2];

    star2.translatesAutoresizingMaskIntoConstraints = NO;
    [star2.centerXAnchor constraintEqualToAnchor:psiCashView.balance.trailingAnchor constant:20].active = YES;
    [star2.centerYAnchor constraintEqualToAnchor:psiCashView.meter.topAnchor constant:2].active = YES;
    [star2.widthAnchor constraintEqualToConstant:25].active = YES;
    [star2.heightAnchor constraintEqualToAnchor:star2.widthAnchor].active = YES;

    StarView *star3 = [[StarView alloc] init];
    [self.view addSubview:star3];

    star3.translatesAutoresizingMaskIntoConstraints = NO;
    [star3.centerXAnchor constraintEqualToAnchor:psiCashView.balance.leadingAnchor constant:-13].active = YES;
    [star3.centerYAnchor constraintEqualToAnchor:psiCashView.balance.centerYAnchor constant:-5].active = YES;
    [star3.widthAnchor constraintEqualToConstant:12].active = YES;
    [star3.heightAnchor constraintEqualToAnchor:star3.widthAnchor].active = YES;

    CGFloat minAlpha = 0.2;
    [star1 blinkWithPeriod:2 andDelay:0 andMinAlpha:minAlpha];
    [star2 blinkWithPeriod:3 andDelay:.25 andMinAlpha:minAlpha];
    [star3 blinkWithPeriod:4 andDelay:.75 andMinAlpha:minAlpha];

    stars = @[star1, star2, star3];
}

- (void)setPsiCashContentHidden:(BOOL)hidden {
    [self setStarsHidden:hidden];
    psiCashView.hidden = hidden;
    psiCashViewHeight.constant = hidden ? 0 : 100;
    psiCashRewardedVideoBar.hidden = hidden;
    psiCashRewardedVideoBarHeight.constant = hidden ? 0 : 100;
}

- (void)setStarsHidden:(BOOL)hidden {
    for (StarView *star in stars) {
        star.hidden = hidden;
    }
}

#pragma mark - PsiCash rewarded videos

- (void)addPsiCashRewardedVideoBar {
    psiCashRewardedVideoBar = [[PsiCashRewardedVideoBar alloc] init];
    psiCashRewardedVideoBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:psiCashRewardedVideoBar];

    UITapGestureRecognizer *rewardedVideoBarTap = [[UITapGestureRecognizer alloc]
                                                   initWithTarget:self action:@selector(showRewardedVideo)];

    rewardedVideoBarTap.numberOfTapsRequired = 1;
    [psiCashRewardedVideoBar addGestureRecognizer:rewardedVideoBarTap];

    [psiCashRewardedVideoBar.centerXAnchor constraintEqualToAnchor:appSubTitleLabel.centerXAnchor].active = YES;
    [psiCashRewardedVideoBar.topAnchor constraintEqualToAnchor:psiCashView.bottomAnchor].active = YES;
    [psiCashRewardedVideoBar.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.7].active = YES;
    psiCashRewardedVideoBarHeight = [psiCashView.heightAnchor constraintEqualToConstant:100];
    psiCashRewardedVideoBarHeight.active = YES;

    // Signals

    [self.compoundDisposable addDisposable:[[[AdManager sharedInstance].rewardedVideoCanPresent
      combineLatestWith:PsiCashClient.sharedInstance.clientModelSignal]
      subscribeNext:^(RACTwoTuple<NSNumber *, PsiCashClientModel *> *x) {
          BOOL ready = [[x first] boolValue];
          PsiCashClientModel *model = [x second];

          psiCashRewardedVideoBar.userInteractionEnabled = ready && [model.authPackage hasEarnerToken];
          [psiCashRewardedVideoBar videoReady:ready && [model.authPackage hasEarnerToken]];

#if DEBUG
          if ([AppInfo runningUITest]) {
              // Fake the rewarded video bar enabled status for automated screenshots.
              [psiCashRewardedVideoBar videoReady:TRUE];
          }
#endif
      }]];
}

- (void)showRewardedVideo {

    MainViewController *__weak weakSelf = self;

    LOG_DEBUG(@"rewarded video started");
    [PsiFeedbackLogger infoWithType:RewardedVideoLogType message:@"started"];

    RACDisposable *__block disposable = [[[[self.adManager
        presentRewardedVideoOnViewController:self
                              withCustomData:[[PsiCashClient sharedInstance] rewardedVideoCustomData]]
        doNext:^(NSNumber *adPresentationEnum) {
            // Logs current AdPresentation enum value.
            AdPresentation ap = (AdPresentation) [adPresentationEnum integerValue];
            switch (ap) {
                case AdPresentationWillAppear:
                    LOG_DEBUG(@"rewarded video AdPresentationWillAppear");
                    break;
                case AdPresentationDidAppear:
                    LOG_DEBUG(@"rewarded video AdPresentationDidAppear");
                    break;
                case AdPresentationWillDisappear:
                    LOG_DEBUG(@"rewarded video AdPresentationWillDisappear");
                    break;
                case AdPresentationDidDisappear:
                    LOG_DEBUG(@"rewarded video AdPresentationDidDisappear");
                    break;
                case AdPresentationDidRewardUser:
                    LOG_DEBUG(@"rewarded video AdPresentationDidRewardUser");
                    break;
                case AdPresentationErrorCustomDataNotSet:
                    LOG_DEBUG(@"rewarded video AdPresentationErrorCustomDataNotSet");
                    break;
                case AdPresentationErrorInappropriateState:
                    LOG_DEBUG(@"rewarded video AdPresentationErrorInappropriateState");
                    [PsiFeedbackLogger errorWithType:RewardedVideoLogType message:@"AdPresentationErrorInappropriateState"];
                    break;
                case AdPresentationErrorNoAdsLoaded:
                    LOG_DEBUG(@"rewarded video AdPresentationErrorNoAdsLoaded");
                    [PsiFeedbackLogger errorWithType:RewardedVideoLogType message:@"AdPresentationErrorNoAdsLoaded"];
                    break;
                case AdPresentationErrorFailedToPlay:
                    LOG_DEBUG(@"rewarded video AdPresentationErrorFailedToPlay");
                    [PsiFeedbackLogger errorWithType:RewardedVideoLogType message:@"AdPresentationErrorFailedToPlay"];
                    break;
            }
        }]
        scanWithStart:[RACTwoTuple pack:@(FALSE) :@(FALSE)]
               reduce:^RACTwoTuple<NSNumber *, NSNumber *> *(RACTwoTuple *running, NSNumber *adPresentationEnum) {

            // Scan operator's `running` value is a 2-tuple of booleans. First element represents when
            // AdPresentationDidRewardUser is emitted upstream, and the second element represents when
            // AdPresentationDidDisappear is emitted upstream.
            // Note that we don't want to make any assumptions about the order of these two events.
            if ([adPresentationEnum integerValue] == AdPresentationDidRewardUser) {
                return [RACTwoTuple pack:@(TRUE) :running.second];
            } else if ([adPresentationEnum integerValue] == AdPresentationDidDisappear) {
                return [RACTwoTuple pack:running.first :@(TRUE)];
            }
            return running;
        }]
        subscribeNext:^(RACTwoTuple<NSNumber *, NSNumber *> *tuple) {
            // Calls to update PsiCash balance after
            BOOL didReward = [tuple.first boolValue];
            BOOL didDisappear = [tuple.second boolValue];
            if (didReward && didDisappear) {
                [[PsiCashClient sharedInstance] pollForBalanceDeltaWithMaxRetries:30 andTimeBetweenRetries:1.0];
            }
        } error:^(NSError *error) {
            [PsiFeedbackLogger errorWithType:RewardedVideoLogType message:@"Error with rewarded video" object:error];
            [weakSelf.compoundDisposable removeDisposable:disposable];
        } completed:^{
            LOG_DEBUG(@"rewarded video completed");
            [PsiFeedbackLogger infoWithType:RewardedVideoLogType message:@"completed"];
            [weakSelf.compoundDisposable removeDisposable:disposable];
        }];

        [self.compoundDisposable addDisposable:disposable];
}

#pragma mark - PsiCashPurchaseAlertViewDelegate protocol

- (void)stateBecameStale {
    [alertView close];
    alertView = nil;
}

- (void)showPsiCashAlertView {
    if (alertView != nil) {
        [alertView close];
        alertView = nil;
    }

    if (![model hasAuthPackage] || ![model.authPackage hasSpenderToken]) {
        return;
    } else if ([model hasActiveSpeedBoostPurchase]) {
        alertView = [PsiCashPurchaseAlertView alreadySpeedBoostingAlert];
    } else  if ([model hasPendingPurchase]) {
        // (PsiCash 1.0): Do nothing
        //alertView = [PsiCashPurchaseAlertView pendingPurchaseAlert];
        return;
    } else {
        // Insufficient balance animation
        CABasicAnimation *animation =
        [CABasicAnimation animationWithKeyPath:@"position"];
        [animation setDuration:0.075];
        [animation setRepeatCount:3];
        [animation setAutoreverses:YES];
        [animation setFromValue:[NSValue valueWithCGPoint:
                                 CGPointMake([psiCashView center].x - 20.0f, [psiCashView center].y)]];
        [animation setToValue:[NSValue valueWithCGPoint:
                               CGPointMake([psiCashView center].x + 20.0f, [psiCashView center].y)]];
        [[psiCashView layer] addAnimation:animation forKey:@"position"];
        return;
    }

    alertView.controllerDelegate = self;
    [alertView bindWithModel:model];
    [alertView show];
}


#pragma mark - PsiCashOnboardingViewControllerDelegate protocol implementation

- (void)onboardingEnded {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PsiCashHasBeenOnboardedBoolKey];
    for (StarView *star in stars) {
        [star removeFromSuperview];
    }
}

#pragma mark - RegionAdapterDelegate protocol implementation

- (void)selectedRegionDisappearedThenSwitchedToBestPerformance {
    dispatch_async_main(^{
        [self updateRegionButton];
    });
    [self persistSelectedRegion];
}

@end
