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
#import "IAPStoreHelper.h"
#import "IAPViewController.h"
#import "LaunchScreenViewController.h"
#import "Logging.h"
#import "LogViewControllerFullScreen.h"
#import "PsiFeedbackLogger.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonConfigUserDefaults.h"
#import "RegionSelectionViewController.h"
#import "SharedConstants.h"
#import "NEBridge.h"
#import "NSString+Additions.h"
#import "Notifier.h"
#import "UIAlertController+Delegate.h"
#import "UpstreamProxySettings.h"
#import "RACCompoundDisposable.h"
#import "RACTuple.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"
#import "RACSignal+Operations.h"
#import "RACSignal.h"
#import "RACUnit.h"
#import "RegionSelectionButton.h"
#import "NSNotificationCenter+RACSupport.h"
#import "PrivacyPolicyViewController.h"
#import "PsiCashRewardedVideoButton.h"
#import "PsiCashBalanceView.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostMeterView.h"
#import "PsiCashView.h"
#import "SubscriptionsBar.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"
#import "UILabel+GetLabelHeight.h"
#import "VPNManager.h"
#import "VPNStartAndStopButton.h"

PsiFeedbackLogType const RewardedVideoLogType = @"RewardedVideo";

UserDefaultsKey const PrivacyPolicyAcceptedBoolKey = @"PrivacyPolicy.AcceptedBoolKey";
UserDefaultsKey const PsiCashHasBeenOnboardedBoolKey = @"PsiCash.HasBeenOnboarded";

@interface MainViewController ()

@property (nonatomic) RACCompoundDisposable *compoundDisposable;
@property (nonatomic) AdManager *adManager;
@property (nonatomic) VPNManager *vpnManager;

@end

@implementation MainViewController {
    // Models
    AvailableServerRegions *availableServerRegions;

    // UI elements
    UILabel *statusLabel;
    UILabel *versionLabel;
    SubscriptionsBar *subscriptionsBar;
    RegionSelectionButton *regionSelectionButton;
    VPNStartAndStopButton *startAndStopButton;
    
    // UI Constraint
    NSLayoutConstraint *startButtonWidth;
    NSLayoutConstraint *startButtonHeight;
    
    // Settings
    PsiphonSettingsViewController *appSettingsViewController;
    UIButton *settingsButton;
    
    // Region Selection
    UINavigationController *regionSelectionNavController;
    UIView *bottomBar;
    CAGradientLayer *bottomBarGradient;
    NSString *selectedRegionSnapShot;
    
    FeedbackManager *feedbackManager;

    // PsiCash
    NSLayoutConstraint *psiCashViewHeight;
    PsiCashPurchaseAlertView *alertView;
    PsiCashClientModel *model;
    PsiCashView *psiCashView;
    RACDisposable *psiCashViewUpdates;

    // Clouds
    UIImageView *cloudMiddleLeft;
    UIImageView *cloudTopRight;
    UIImageView *cloudBottomRight;
    NSLayoutConstraint *cloudMiddleLeftHorizontalConstraint;
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
- (id)init {
    self = [super init];
    if (self) {
        
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
        
        _vpnManager = [VPNManager sharedInstance];
        
        _adManager = [AdManager sharedInstance];
        
        feedbackManager = [[FeedbackManager alloc] init];
        
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

    availableServerRegions = [[AvailableServerRegions alloc] init];
    [availableServerRegions sync];
    
    // Setting up the UI
    // calls them in the right order
    [self.view setBackgroundColor:[UIColor whiteColor]];
    [self setNeedsStatusBarAppearanceUpdate];
    [self addViews];

    [self setupClouds];
    [self setupVersionLabel];
    [self setupSettingsButton];
    [self setupPsiCashView];
    [self setupStartAndStopButton];
    [self setupStatusLabel];
    [self setupRegionSelectionButton];
    [self setupBottomBar];
    [self setupAddSubscriptionsBar];

    __weak MainViewController *weakSelf = self;
    
    // Observe VPN status for updating UI state
    RACDisposable *tunnelStatusDisposable = [self.vpnManager.lastTunnelStatus
      subscribeNext:^(NSNumber *statusObject) {
          VPNStatus s = (VPNStatus) [statusObject integerValue];

          [weakSelf updateUIConnectionState:s];

          if (s == VPNStatusConnecting ||
              s == VPNStatusRestarting ||
              s == VPNStatusReasserting) {
              // TODO: start connection animation
          } else {
              // TODO: remove connection animation
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
              [startAndStopButton setHighlighted:TRUE];
          } else {
              [startAndStopButton setHighlighted:FALSE];
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

          [subscriptionsBar subscriptionActive:(s == UserSubscriptionActive)];

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
    // TODO: maybe have availableServerRegions listen to a global signal?
    [availableServerRegions sync];
    [regionSelectionButton update];
    
    if (self.openSettingImmediatelyOnViewDidAppear) {
        [self openSettingsMenu];
        self.openSettingImmediatelyOnViewDidAppear = NO;
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
    return UIStatusBarStyleDefault;
}

// Reload when rotate
- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {

    [self setStartButtonSizeConstraints:size];
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

#pragma mark - UI callbacks

- (void)onStartStopTap:(UIButton *)sender {

    __weak MainViewController *weakSelf = self;

    // Emits unit value if/when the privacy policy is accepted.
    RACSignal *privacyPolicyAccepted =
      [[RACSignal return:@([NSUserDefaults.standardUserDefaults boolForKey:PrivacyPolicyAcceptedBoolKey])]
      flattenMap:^RACSignal<RACUnit *> *(NSNumber *ppAccepted) {

        if ([ppAccepted boolValue]) {
            return [RACSignal return:RACUnit.defaultUnit];
        } else {

            PrivacyPolicyViewController *c = [[PrivacyPolicyViewController alloc] init];
            [self presentViewController:c animated:TRUE completion:nil];

            return [[[[NSNotificationCenter defaultCenter]
              rac_addObserverForName:PrivacyPolicyAcceptedNotification
                              object:nil]
              take:1]
              map:^id(NSNotification *value) {
                  [NSUserDefaults.standardUserDefaults setBool:TRUE forKey:PrivacyPolicyAcceptedBoolKey];
                  return RACUnit.defaultUnit;
              }];
        }

    }];


    NSString * const CommandNoInternetAlert = @"NoInternetAlert";
    NSString * const CommandStartTunnel = @"StartTunnel";
    NSString * const CommandStopVPN = @"StopVPN";
    NSString * const CommandConnectOnDemandAlert = @"ConnectOnDemandAlert";

    // signal emits a single two tuple (isVPNActive, connectOnDemandEnabled).
    __block RACDisposable *disposable = [[[[[privacyPolicyAccepted
      flattenMap:^RACSignal<RACTwoTuple <NSNumber *, NSNumber *> *> *(RACUnit *x) {
          return [weakSelf.vpnManager isVPNActive];
      }]
      flattenMap:^RACSignal<RACTwoTuple<NSNumber *, NSNumber *> *> *(RACTwoTuple<NSNumber *, NSNumber *> *value) {
          // Returned signal emits tuple (isActive, isConnectOnDemandEnabled).

          // If VPN is already running, checks if ConnectOnDemand is enabled, otherwise returns the result immediately.
          BOOL isActive = [value.first boolValue];
          if (isActive) {
              return [[weakSelf.vpnManager isConnectOnDemandEnabled]
                      map:^RACTwoTuple<NSNumber *, NSNumber *> *(NSNumber *connectOnDemandEnabled) {
                          return [RACTwoTuple pack:@(TRUE) :connectOnDemandEnabled];
                      }];
          } else {
              return [RACSignal return:[RACTwoTuple pack:@(FALSE) :@(FALSE)]];
          }
      }]
      flattenMap:^RACSignal<NSString *> *(RACTwoTuple<NSNumber *, NSNumber *> *value) {
          BOOL vpnActive = [value.first boolValue];
          BOOL connectOnDemandEnabled = [value.second boolValue];

          // Emits command to stop VPN if it has already started. Otherwise, it checks for internet connectivity
          // and emits one of CommandNoInternetAlert or CommandStartTunnel.
          if (vpnActive) {
              if (connectOnDemandEnabled) {
                  return [RACSignal return:CommandConnectOnDemandAlert];
              } else {
                  return [RACSignal return:CommandStopVPN];
              }

          } else {
              // Alerts the user if there is no internet connection.
              Reachability *reachability = [Reachability reachabilityForInternetConnection];
              if ([reachability currentReachabilityStatus] == NotReachable) {
                  return [RACSignal return:CommandNoInternetAlert];

              } else {

                  // Returned signal checks whether or not VPN configuration is already installed.
                  // Skips presenting ads if there is not VPN configuration installed.
                  return [[weakSelf.vpnManager vpnConfigurationInstalled]
                    flattenMap:^RACSignal *(NSNumber *value) {
                        BOOL vpnInstalled = [value boolValue];

                        if (!vpnInstalled) {
                            return [RACSignal return:CommandStartTunnel];
                        } else {
                            // Start tunnel after ad presentation signal completes.
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
            [[AppDelegate sharedAppDelegate] displayAlertNoInternet];

        } else if ([CommandConnectOnDemandAlert isEqualToString:command]) {
            // Alert the user that Connect On Demand is enabled, and if they
            // would like Connect On Demand to be disabled, and the extension to be stopped.
            NSString *alertTitle = NSLocalizedStringWithDefaultValue(@"CONNECT_ON_DEMAND_ALERT_TITLE", nil, [NSBundle mainBundle], @"Auto-start VPN is enabled", @"Alert dialog title informing user that 'Auto-start VPN' feature is enabled");
            NSString *alertMessage = NSLocalizedStringWithDefaultValue(@"CONNECT_ON_DEMAND_ALERT_BODY", nil, [NSBundle mainBundle], @"\"Auto-start VPN\" will be temporarily disabled until the next time Psiphon VPN is started.", "Alert dialog body informing the user that the 'Auto-start VPN on demand' feature will be disabled and that the VPN cannot be stopped.");

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                           message:alertMessage
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *stopUntilNextStartAction = [UIAlertAction
              actionWithTitle:NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"OK button title")
                        style:UIAlertActionStyleDefault
                      handler:^(UIAlertAction *action) {

                          // Disable "Connect On Demand" and stop the VPN.
                          [[NSUserDefaults standardUserDefaults] setBool:TRUE
                                                                  forKey:VPNManagerConnectOnDemandUntilNextStartBoolKey];

                          __block RACDisposable *disposable = [[weakSelf.vpnManager setConnectOnDemandEnabled:FALSE]
                            subscribeNext:^(NSNumber *x) {
                                // Stops the VPN only after ConnectOnDemand is disabled.
                                [weakSelf.vpnManager stopVPN];
                            } error:^(NSError *error) {
                                [weakSelf.compoundDisposable removeDisposable:disposable];
                            }   completed:^{
                                [weakSelf.compoundDisposable removeDisposable:disposable];
                            }];

                          [weakSelf.compoundDisposable addDisposable:disposable];
                      }];

            [alert addAction:stopUntilNextStartAction];
            [weakSelf presentViewController:alert animated:TRUE completion:nil];
        }

    } error:^(NSError *error) {
        [weakSelf.compoundDisposable removeDisposable:disposable];
    } completed:^{
        [weakSelf.compoundDisposable removeDisposable:disposable];
    }];
    
    [self.compoundDisposable addDisposable:disposable];
}

- (void)onSettingsButtonTap:(UIButton *)sender {
    [self openSettingsMenu];
}

- (void)onRegionSelectionButtonTap:(UIButton *)sender {
    [self openRegionSelection];
}

- (void)onSubscriptionTap {
    [self openIAPViewController];
}

#if DEBUG
- (void)onVersionLabelTap:(UILabel *)sender {
    TabbedLogViewController *viewController = [[TabbedLogViewController alloc] initWithCoder:nil];
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

- (BOOL)isRightToLeft {
    return ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);
}

- (void)setupSettingsButton {
    UIImage *gearTemplate = [UIImage imageNamed:@"settings"];
    settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [settingsButton setImage:gearTemplate forState:UIControlStateNormal];

    // Setup autolayout
    CGFloat buttonTouchAreaSize = 80.f;
    [settingsButton.topAnchor constraintEqualToAnchor:psiCashView.topAnchor constant:-(buttonTouchAreaSize - gearTemplate.size.height)/2].active = YES;
    [settingsButton.trailingAnchor constraintEqualToAnchor:psiCashView.trailingAnchor constant:(buttonTouchAreaSize/2 - gearTemplate.size.width/2)].active = YES;
    [settingsButton.widthAnchor constraintEqualToConstant:buttonTouchAreaSize].active = YES;
    [settingsButton.heightAnchor constraintEqualToAnchor:settingsButton.widthAnchor].active = YES;

    [settingsButton addTarget:self action:@selector(onSettingsButtonTap:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)updateUIConnectionState:(VPNStatus)s {
    [self positionClouds:s];

    [startAndStopButton setHighlighted:FALSE];
    
    if ([VPNManager mapIsVPNActive:s] && s != VPNStatusConnected) {
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

// Add all views at the same time so there are no crashes while
// adding and activating autolayout constraints.
- (void)addViews {
    UIImage *cloud = [UIImage imageNamed:@"cloud"];
    cloudMiddleLeft = [[UIImageView alloc] initWithImage:cloud];
    cloudTopRight = [[UIImageView alloc] initWithImage:cloud];
    cloudBottomRight = [[UIImageView alloc] initWithImage:cloud];
    versionLabel = [[UILabel alloc] init];
    settingsButton = [[UIButton alloc] init];
    psiCashView = [[PsiCashView alloc] init];
    startAndStopButton = [VPNStartAndStopButton buttonWithType:UIButtonTypeCustom];
    statusLabel = [[UILabel alloc] init];
    regionSelectionButton = [[RegionSelectionButton alloc] init];
    bottomBar = [[UIView alloc] init];
    subscriptionsBar = [[SubscriptionsBar alloc] init];

    // NOTE: some views overlap so the order they are added
    //       is important for user interaction.
    [self.view addSubview:cloudMiddleLeft];
    [self.view addSubview:cloudTopRight];
    [self.view addSubview:cloudBottomRight];
    [self.view addSubview:psiCashView];
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

    cloudTopRight.translatesAutoresizingMaskIntoConstraints = NO;
    [cloudTopRight.topAnchor constraintEqualToAnchor:psiCashView.bottomAnchor constant:-20].active = YES;
    [cloudTopRight.heightAnchor constraintEqualToConstant:cloud.size.height].active = YES;
    [cloudTopRight.widthAnchor constraintEqualToConstant:cloud.size.width].active = YES;

    cloudBottomRight.translatesAutoresizingMaskIntoConstraints = NO;
    [cloudBottomRight.centerYAnchor constraintEqualToAnchor:regionSelectionButton.topAnchor constant:-24].active = YES;
    [cloudBottomRight.heightAnchor constraintEqualToConstant:cloud.size.height].active = YES;
    [cloudBottomRight.widthAnchor constraintEqualToConstant:cloud.size.width].active = YES;

    // Default horizontal positioning for clouds
    cloudMiddleLeftHorizontalConstraint = [cloudMiddleLeft.centerXAnchor constraintEqualToAnchor:self.view.leftAnchor constant:0];
    cloudTopRightHorizontalConstraint = [cloudTopRight.centerXAnchor constraintEqualToAnchor:self.view.rightAnchor constant:0];
    cloudBottomRightHorizontalConstraint = [cloudBottomRight.centerXAnchor constraintEqualToAnchor:self.view.rightAnchor constant:0];

    cloudMiddleLeftHorizontalConstraint.active = YES;
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
        [cloudMiddleLeft.layer removeAllAnimations];
        [cloudTopRight.layer removeAllAnimations];
        [cloudBottomRight.layer removeAllAnimations];
    };

    // Position clouds in their default positions
    void (^disconnectedAndConnectedLayout)(void) = ^void(void) {
        cloudMiddleLeftHorizontalConstraint.constant = cloudMiddleLeftOffset;
        cloudTopRightHorizontalConstraint.constant = cloudTopRightOffset;
        cloudBottomRightHorizontalConstraint.constant = cloudBottomRightOffset;
        [self.view layoutIfNeeded];
    };

    if ([VPNManager mapIsVPNActive:s] && s != VPNStatusConnected) {
        // Connecting

        void (^connectingLayout)(void) = ^void(void) {
            cloudMiddleLeftHorizontalConstraint.constant = self.view.frame.size.width + cloudMiddleLeftOffset + 1.f/6*cloudWidth;
            cloudTopRightHorizontalConstraint.constant = -3.f/4 * self.view.frame.size.width + cloudTopRightOffset;
            cloudBottomRightHorizontalConstraint.constant = -3.f/4 * self.view.frame.size.width + cloudBottomRightOffset;
            [self.view layoutIfNeeded];
        };

        if (!([VPNManager mapIsVPNActive:previousState] && previousState != VPNStatusConnected)
            && previousState != VPNStatusInvalid /* don't animate if the app was just opened */ ) {

            removeAllCloudAnimations();

            // Move middle left cloud to the right so it can animate in from the right side.
            cloudMiddleLeftHorizontalConstraint.constant = self.view.frame.size.width * 2;
            [self.view layoutIfNeeded];

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

                cloudMiddleLeftHorizontalConstraint.constant = self.view.frame.size.width + cloudWidth/2 + cloudMiddleLeftOffset;
                cloudTopRightHorizontalConstraint.constant = -self.view.frame.size.width - cloudWidth/2 + cloudTopRightOffset;
                cloudBottomRightHorizontalConstraint.constant = -self.view.frame.size.width - cloudWidth/2 + cloudBottomRightOffset;
                [self.view layoutIfNeeded];

            } completion:^(BOOL finished) {

                if (finished) {
                    // We want all the clouds to animate at the same speed so we put them all at the
                    // same distance from their final point.
                    CGFloat maxOffset = MAX(MAX(ABS(cloudMiddleLeftOffset), ABS(cloudTopRightOffset)), ABS(cloudBottomRightOffset));
                    cloudMiddleLeftHorizontalConstraint.constant = -cloudWidth/2 - (maxOffset + cloudMiddleLeftOffset);
                    cloudTopRightHorizontalConstraint.constant = cloudWidth/2 + (maxOffset + cloudTopRightOffset);
                    cloudBottomRightHorizontalConstraint.constant = cloudWidth/2 + (maxOffset + cloudBottomRightOffset);
                    [self.view layoutIfNeeded];

                    [UIView animateWithDuration:0.25 * animationTimeStretchFactor delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                        disconnectedAndConnectedLayout();
                    } completion:nil];
                }
            }];
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
    statusLabel.textColor = [UIColor colorWithRed:0.88 green:0.87 blue:0.87 alpha:1.0];
    statusLabel.font = [UIFont avenirNextBold:14.5];
    
    // Setup autolayout
    CGFloat labelHeight = [statusLabel getLabelHeight];
    [statusLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;
    [statusLabel.topAnchor constraintEqualToAnchor:startAndStopButton.bottomAnchor constant:5].active = YES;
    [statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)setStatusLabelText:(NSString*)s {
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc] initWithString:s];
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
    [bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;

    bottomBarGradient = [CAGradientLayer layer];

    bottomBarGradient.frame = bottomBar.bounds; // frame reset in viewDidLayoutSubviews
    bottomBarGradient.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor, (id)UIColor.lightishBlue.CGColor];

    [bottomBar.layer insertSublayer:bottomBarGradient atIndex:0];
}

- (void)setupRegionSelectionButton {
    regionSelectionButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    CGFloat buttonHeight = 58;
    [regionSelectionButton addTarget:self action:@selector(onRegionSelectionButtonTap:) forControlEvents:UIControlEventTouchUpInside];

    // Set button height
    [regionSelectionButton.heightAnchor constraintEqualToConstant:buttonHeight].active = YES;

    [regionSelectionButton update];

    // Add constraints
    NSLayoutConstraint *idealBottomSpacing = [regionSelectionButton.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:-31.f];
    [idealBottomSpacing setPriority:999];
    idealBottomSpacing.active = YES;
    [regionSelectionButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [regionSelectionButton.widthAnchor constraintEqualToAnchor:bottomBar.widthAnchor multiplier:.856].active = YES;
}

- (void)setupVersionLabel {
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.text = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"APP_VERSION", nil, [NSBundle mainBundle], @"v.%@", @"Text showing the app version. The '%@' placeholder is the version number. So it will look like 'v.2'."),[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    versionLabel.userInteractionEnabled = YES;
    versionLabel.textColor = UIColor.offWhiteTwo;
    versionLabel.font = [UIFont avenirNextBold:10.5f];

#if DEBUG
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self action:@selector(onVersionLabelTap:)];
    tapRecognizer.numberOfTapsRequired = 1;
    [versionLabel addGestureRecognizer:tapRecognizer];
#endif

    // Setup autolayout
    [versionLabel.leadingAnchor constraintEqualToAnchor:psiCashView.leadingAnchor constant:0].active = YES;
    [versionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:psiCashView.balance.leadingAnchor constant:-2].active = YES;
    [versionLabel.topAnchor constraintEqualToAnchor:psiCashView.topAnchor].active = YES;
}

- (void)setupAddSubscriptionsBar {
    // Setup autolayout
    subscriptionsBar.translatesAutoresizingMaskIntoConstraints = NO;

    [subscriptionsBar.heightAnchor constraintEqualToConstant:79].active = YES;
    [subscriptionsBar.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [subscriptionsBar.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor constant:0].active = YES;
    if (@available(iOS 11.0, *)) {
        [subscriptionsBar.bottomAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.bottomAnchor constant:-7].active = TRUE;
    } else {
        [subscriptionsBar.bottomAnchor constraintEqualToAnchor:bottomBar.bottomAnchor constant:-7].active = YES;
    }
    [subscriptionsBar.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:1.f constant:0].active = YES;

    [subscriptionsBar addTarget:self
                         action:@selector(onSubscriptionTap)
               forControlEvents:UIControlEventTouchUpInside];
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

    if (![NSString stringsBothEqualOrNil:selectedRegion b:selectedRegionSnapShot]) {
        [self persistSelectedRegion];
        [regionSelectionButton update];
        [self.vpnManager restartVPNIfActive];
    }
    [regionSelectionNavController dismissViewControllerAnimated:YES completion:nil];
    regionSelectionNavController = nil;
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

#pragma mark - PsiCash UI actions

/**
 * Buy max num hours of Speed Boost that the user can afford if possible
 */
- (void)instantMaxSpeedBoostPurchase {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    if (![userDefaults boolForKey:PsiCashHasBeenOnboardedBoolKey]) {
        // TODO: onboarding fitting ui-3
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

- (void)setupPsiCashView {
    psiCashView.translatesAutoresizingMaskIntoConstraints = NO;

    UITapGestureRecognizer *psiCashViewTap = [[UITapGestureRecognizer alloc]
                                                  initWithTarget:self action:@selector(instantMaxSpeedBoostPurchase)];

    psiCashViewTap.numberOfTapsRequired = 1;
    [psiCashView.meter addGestureRecognizer:psiCashViewTap];

    [psiCashView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [psiCashView.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:26].active = YES;

    CGFloat psiCashViewMaxWidth = 400;
    CGFloat psiCashViewToParentViewWidthRatio = 0.909;
    if (self.view.frame.size.width * psiCashViewToParentViewWidthRatio > psiCashViewMaxWidth) {
        [psiCashView.widthAnchor constraintEqualToConstant:psiCashViewMaxWidth].active = YES;
    } else {
        [psiCashView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:psiCashViewToParentViewWidthRatio].active = YES;
    }
    psiCashViewHeight = [psiCashView.heightAnchor constraintEqualToConstant:146.9];
    psiCashViewHeight.active = YES;

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
                [PsiCashView animateBalanceChangeOf:balanceChange
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

    [self.compoundDisposable addDisposable:[[[AdManager sharedInstance].rewardedVideoCanPresent
                                             combineLatestWith:PsiCashClient.sharedInstance.clientModelSignal]
                                            subscribeNext:^(RACTwoTuple<NSNumber *, PsiCashClientModel *> *x) {
                                                BOOL ready = [[x first] boolValue];
                                                PsiCashClientModel *model = [x second];

                                                psiCashView.rewardedVideoButton.userInteractionEnabled = ready && [model.authPackage hasEarnerToken];
                                                [psiCashView.rewardedVideoButton videoReady:ready && [model.authPackage hasEarnerToken]];

#if DEBUG
                                                if ([AppInfo runningUITest]) {
                                                    // Fake the rewarded video bar enabled status for automated screenshots.
                                                    [psiCashView.rewardedVideoButton videoReady:TRUE];
                                                }
#endif
                                            }]];

        UITapGestureRecognizer *rewardedVideoButtonTap = [[UITapGestureRecognizer alloc]
                                                       initWithTarget:self action:@selector(showRewardedVideo)];

        rewardedVideoButtonTap.numberOfTapsRequired = 1;
        [psiCashView.rewardedVideoButton addGestureRecognizer:rewardedVideoButtonTap];

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

- (void)setPsiCashContentHidden:(BOOL)hidden {
    psiCashView.hidden = hidden;
    psiCashView.userInteractionEnabled = !hidden;
}

- (void)showRewardedVideo {

    LOG_DEBUG(@"rewarded video started");
    [PsiFeedbackLogger infoWithType:RewardedVideoLogType message:@"started"];

    RACSignal *showVideo = [self.adManager presentRewardedVideoOnViewController:self
      withCustomData:[[PsiCashClient sharedInstance] rewardedVideoCustomData]];

    [self.compoundDisposable addDisposable:[showVideo subscribeNext:^(NSNumber *value) {
        AdPresentation ap = (AdPresentation) [value integerValue];

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
                [[PsiCashClient sharedInstance] pollForBalanceDeltaWithMaxRetries:30 andTimeBetweenRetries:1.0];
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

    } error:^(NSError *error) {
        [PsiFeedbackLogger errorWithType:RewardedVideoLogType message:@"Error with rewarded video" object:error];
    } completed:^{
        LOG_DEBUG(@"rewarded video completed");
        [PsiFeedbackLogger infoWithType:RewardedVideoLogType message:@"completed"];
    }]];
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
}

#pragma mark - RegionAdapterDelegate protocol implementation

- (void)selectedRegionDisappearedThenSwitchedToBestPerformance {
    MainViewController __weak *weakSelf = self;
    dispatch_async_main(^{
        MainViewController __strong *strongSelf = weakSelf;
        [strongSelf->regionSelectionButton update];
    });
    [self persistSelectedRegion];
}

@end
