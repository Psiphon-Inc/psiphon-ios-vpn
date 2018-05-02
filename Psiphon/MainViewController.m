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
#import "AppDelegate.h"
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
#import "Asserts.h"

#import "PsiCashBalanceView.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostMeterView.h"
#import "PsiCashTableViewController.h"


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
    UILabel *adLabel;
    UIButton *subscriptionButton;
    UILabel *regionButtonHeader;
    UIButton *regionButton;
    UIButton *startStopButton;
    PulsingHaloLayer *startStopButtonHalo;
    BOOL isStartStopButtonHaloOn;
    
    // UI Constraint
    NSLayoutConstraint *startButtonScreenWidth;
    NSLayoutConstraint *startButtonScreenHeight;
    NSLayoutConstraint *startButtonWidth;
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
    
    UIAlertController *alertControllerNoInternet;
    
    FeedbackManager *feedbackManager;

    // PsiCash
    PsiCashPurchaseAlertView *alertView;
    PsiCashSpeedBoostMeterView *speedBoostMeter;
    PsiCashClientModel *model;
    PsiCashBalanceView *balanceView;
    RACDisposable * balanceViewUpdates;
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

- (void) dealloc {
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
    [self addAdLabel];
    [self addAppTitleLabel];
    [self addAppSubTitleLabel];
    [self addSubscriptionButton];
    [self addPsiCashBalanceView];
    [self addStatusLabel];
    [self addVersionLabel];
    [self setupLayoutGuides];
    
    if (([[UIDevice currentDevice].model hasPrefix:@"iPhone"] || [[UIDevice currentDevice].model hasPrefix:@"iPod"]) && (self.view.bounds.size.width > self.view.bounds.size.height)) {
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
                                                                              [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString] options:@{} completionHandler:^(BOOL success) {
                                                                                  // Do nothing.
                                                                              }];
                                                                          }];

              UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel
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

          BOOL showPsiCashUI = (s == UserSubscriptionInactive);

          subscriptionButton.hidden = (s == UserSubscriptionActive);
          adLabel.hidden = (s == UserSubscriptionActive) || ![self.adManager untunneledInterstitialIsReady];
          subscriptionButtonTopConstraint.active = !subscriptionButton.hidden;
          bottomBarTopConstraint.active = subscriptionButton.hidden;

          // PsiCash
          appTitleLabel.hidden = showPsiCashUI;
          appSubTitleLabel.hidden = showPsiCashUI;
          speedBoostMeter.hidden = !showPsiCashUI;
          balanceView.hidden = !showPsiCashUI;

      } error:^(NSError *error) {
          [self.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [self.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];

    // Observer AdManager notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAdStatusDidChange)
                                                 name:AdManagerAdsDidLoadNotification
                                               object:self.adManager];
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
    
    // Listen for VPN status changes from VPNManager.
    
    // Sync UI with the VPN state
    [self onAdStatusDidChange];
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
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [self.view removeConstraint:startButtonWidth];
    [self setRegionSelectionConstraints:size];
    
    if (size.width > size.height) {
        [self.view removeConstraint:startButtonScreenWidth];
        [self.view addConstraint:startButtonScreenHeight];
        if ([[UIDevice currentDevice].model hasPrefix:@"iPhone"]) {
            adLabel.hidden = YES;
        }
    } else {
        [self.view removeConstraint:startButtonScreenHeight];
        [self.view addConstraint:startButtonScreenWidth];
        if ([[UIDevice currentDevice].model hasPrefix:@"iPhone"]) {
            adLabel.hidden = ![self.adManager untunneledInterstitialIsReady];
        }
    }
    
    [self.view addConstraint:startButtonWidth];
    
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

- (void)onAdStatusDidChange{
    adLabel.hidden = ![self.adManager untunneledInterstitialIsReady];
}

- (void)onStartStopTap:(UIButton *)sender {
    
    __weak MainViewController *weakSelf = self;
    
    // signal emits a single two tuple (isVPNActive, connectOnDemandEnabled).
    __block RACDisposable *disposable = [[[[self.vpnManager isVPNActive]
      flattenMap:^RACSignal<NSNumber *> *(RACTwoTuple<NSNumber *, NSNumber *> *value) {

          // If VPN is already running, checks if ConnectOnDemand is enabled, otherwise returns the result immediately.
          BOOL isActive = [value.first boolValue];
          if (isActive) {
              return [[weakSelf.vpnManager isConnectOnDemandEnabled]
                      map:^id(NSNumber *connectOnDemandEnabled) {
                          return [RACTwoTuple pack:@(TRUE) :connectOnDemandEnabled];
                      }];
          } else {
              return [RACSignal return:[RACTwoTuple pack:@(FALSE) :@(FALSE)]];
          }
      }]
      deliverOnMainThread]
      subscribeNext:^(RACTwoTuple<NSNumber *, NSNumber *> *result) {

          // Unpacks the tuple.
          BOOL isVPNActive = [result.first boolValue];
          BOOL connectOnDemandEnabled = [result.second boolValue];

          if (!isVPNActive) {
              // Alerts the user if there is no internet connection.
              Reachability *reachability = [Reachability reachabilityForInternetConnection];
              if ([reachability currentReachabilityStatus] == NotReachable) {
                  [weakSelf displayAlertNoInternet];
              } else {
                  [weakSelf.adManager showUntunneledInterstitial];
              }

          } else {

              if (!connectOnDemandEnabled) {

                  [weakSelf.vpnManager stopVPN];

              } else {
                  // Alert the user that Connect On Demand is enabled, and if they
                  // would like Connect On Demand to be disabled, and the extension to be stopped.
                  NSString *alertTitle = NSLocalizedStringWithDefaultValue(@"CONNECT_ON_DEMAND_ALERT_TITLE", nil, [NSBundle mainBundle], @"Auto-start VPN is enabled", @"Alert dialog title informing user that 'Auto-start VPN' feature is enabled");
                  NSString *alertMessage = NSLocalizedStringWithDefaultValue(@"CONNECT_ON_DEMAND_ALERT_BODY", nil, [NSBundle mainBundle], @"Cannot stop the VPN while \"Auto-start VPN\" is enabled.\nWould you like to disable \"Auto-start VPN\" on demand and stop the VPN?", "Alert dialog body informing the user that the 'Auto-start VPN on demand' feature is enabled and that the VPN cannot be stopped. Followed by asking the user if they would like to disable the 'Auto-start VPN on demand' feature, and stop the VPN.");

                  UIAlertController *alert = [UIAlertController
                                              alertControllerWithTitle:alertTitle message:alertMessage preferredStyle:UIAlertControllerStyleAlert];

                  UIAlertAction *disableAction = [UIAlertAction
                    actionWithTitle:NSLocalizedStringWithDefaultValue(@"DISABLE_BUTTON", nil, [NSBundle mainBundle], @"Disable Auto-start VPN and Stop", @"Disable Auto-start VPN feature and Stop the VPN button label")
                    style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {
                        // Disable "Connect On Demand" and stop the VPN.
                        [[NSUserDefaults standardUserDefaults] setBool:FALSE forKey:SettingsConnectOnDemandBoolKey];

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

                  UIAlertAction *cancelAction = [UIAlertAction
                                                 actionWithTitle:NSLocalizedStringWithDefaultValue(@"CANCEL_BUTTON", nil, [NSBundle mainBundle], @"Cancel", @"Alert Cancel button")
                                                 style:UIAlertActionStyleCancel
                                                 handler:^(UIAlertAction *action) {
                                                     // Do nothing
                                                 }];

                  [alert addAction:disableAction];
                  [alert addAction:cancelAction];
                  [self presentViewController:alert animated:TRUE completion:nil];

              }

              [self removePulsingHaloLayer];
          }

    } error:^(NSError *error) {
        [weakSelf.compoundDisposable removeDisposable:disposable];
    }   completed:^{
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

- (void) onSubscriptionTap {
    [self openIAPViewController];
}

#if DEBUG
- (void)onVersionLabelTap:(UILabel *)sender {
    TabbedLogViewController *viewController = [[TabbedLogViewController alloc] initWithCoder:nil];
    [self presentViewController:viewController animated:YES completion:nil];
}
#endif

# pragma mark - UI helper functions

- (void)dismissNoInternetAlert {
    LOG_DEBUG();
    if (alertControllerNoInternet != nil){
        [alertControllerNoInternet dismissViewControllerAnimated:YES completion:nil];
        alertControllerNoInternet = nil;
    }
}

- (void)displayAlertNoInternet {
    if (alertControllerNoInternet == nil){
        alertControllerNoInternet = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedStringWithDefaultValue(@"NO_INTERNET", nil, [NSBundle mainBundle], @"No Internet Connection", @"Alert title informing user there is no internet connection")
                                     message:NSLocalizedStringWithDefaultValue(@"TURN_ON_DATE", nil, [NSBundle mainBundle], @"Turn on cellular data or use Wi-Fi to access data.", @"Alert message informing user to turn on their cellular data or wifi to connect to the internet")
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *defaultAction = [UIAlertAction
                                        actionWithTitle:NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"Alert OK Button")
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *action) {
                                        }];
        
        [alertControllerNoInternet addAction:defaultAction];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissNoInternetAlert) name:@"UIApplicationWillResignActiveNotification" object:nil];
    }
    
    [alertControllerNoInternet presentFromTopController];
}

- (NSString *)getVPNStatusDescription:(VPNStatus) status {
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
    
    backgroundGradient.colors = @[(id)[UIColor colorWithRed:0.17 green:0.17 blue:0.28 alpha:1.0].CGColor, (id)[UIColor colorWithRed:0.28 green:0.36 blue:0.46 alpha:1.0].CGColor];
    
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
    CGFloat labelHeight = [self getLabelHeight:appTitleLabel];
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
    CGFloat labelHeight = [self getLabelHeight:appSubTitleLabel];
    [appSubTitleLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;
    [appSubTitleLabel.topAnchor constraintEqualToAnchor:appTitleLabel.bottomAnchor].active = YES;
    [appSubTitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)addSettingsButton {
    settingsButton = [[UIButton alloc] init];
    UIImage *gearTemplate = [[UIImage imageNamed:@"settings"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [settingsButton setImage:gearTemplate forState:UIControlStateNormal];
    [settingsButton setTintColor:[UIColor whiteColor]];
    [self.view addSubview:settingsButton];
    
    // Setup autolayout
    [settingsButton.centerYAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:gearTemplate.size.height/2 + 8.f].active = YES;
    [settingsButton.centerXAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-gearTemplate.size.width/2 - 13.f].active = YES;
    [settingsButton.widthAnchor constraintEqualToConstant:80].active =  YES;
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
    startButtonScreenHeight = [startStopButton.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:.33f];
    startButtonScreenWidth = [startStopButton.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:.33f];
    startButtonWidth = [startStopButton.heightAnchor constraintEqualToAnchor:startStopButton.widthAnchor];
    
    CGSize viewSize = self.view.bounds.size;
    
    if (viewSize.width > viewSize.height) {
        [self.view addConstraint:startButtonScreenHeight];
    } else {
        [self.view addConstraint:startButtonScreenWidth];
    }
    
    [self.view addConstraint:startButtonWidth];
}

- (void)addAdLabel {
    adLabel = [[UILabel alloc] init];
    adLabel.translatesAutoresizingMaskIntoConstraints = NO;
    adLabel.text = NSLocalizedStringWithDefaultValue(@"AD_LOADED", nil, [NSBundle mainBundle], @"Watch a short video while we get ready to connect you", @"Text for button that tell users there will by a short video ad.");
    adLabel.textAlignment = NSTextAlignmentCenter;
    adLabel.textColor = [UIColor lightGrayColor];
    adLabel.lineBreakMode = NSLineBreakByWordWrapping;
    adLabel.numberOfLines = 0;
    UIFontDescriptor * fontD = [adLabel.font.fontDescriptor
                                fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
    adLabel.font = [UIFont fontWithDescriptor:fontD size:adLabel.font.pointSize - 1];
    [self.view addSubview:adLabel];
    if (![self.adManager untunneledInterstitialIsReady]){
        adLabel.hidden = true;
    }
    
    // Setup autolayout
    [adLabel.bottomAnchor constraintGreaterThanOrEqualToAnchor:startStopButton.topAnchor constant:-30].active = YES;
    [adLabel.bottomAnchor constraintLessThanOrEqualToAnchor:startStopButton.topAnchor constant:-10.f].active = YES;
    [adLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15].active = YES;
    [adLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15].active = YES;
}

- (void)addStatusLabel {
    statusLabel = [[UILabel alloc] init];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.adjustsFontSizeToFitWidth = YES;
    statusLabel.text = [self getVPNStatusDescription:(VPNStatus) [[self.vpnManager.lastTunnelStatus first] integerValue]];
    statusLabel.textAlignment = NSTextAlignmentCenter;
    statusLabel.textColor = [UIColor whiteColor];
    [self.view addSubview:statusLabel];
    
    // Setup autolayout
    CGFloat labelHeight = [self getLabelHeight:statusLabel];
    [statusLabel.heightAnchor constraintEqualToConstant:labelHeight].active = YES;

    NSLayoutConstraint *floatingConstraint = [NSLayoutConstraint constraintWithItem:statusLabel
                                                                          attribute:NSLayoutAttributeTop
                                                                          relatedBy:NSLayoutRelationEqual
                                                                             toItem:startStopButton
                                                                          attribute:NSLayoutAttributeBottom
                                                                         multiplier:1.07f
                                                                           constant:-6];
    // Allow it to break in favour of the next two constraint
    floatingConstraint.priority = 999;
    [self.view addConstraint:floatingConstraint];
    [statusLabel.topAnchor constraintGreaterThanOrEqualToAnchor:startStopButton.bottomAnchor constant:1].active = YES;
    [statusLabel.topAnchor constraintLessThanOrEqualToAnchor:startStopButton.bottomAnchor constant:15].active = YES;
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
    regionButtonHeader.text = NSLocalizedStringWithDefaultValue(@"CHANGE_REGION", nil, [NSBundle mainBundle], @"Change region", @"Text above change region button that allows user to select their desired server region");
    regionButtonHeader.adjustsFontSizeToFitWidth = NO;
    regionButtonHeader.font = [regionButtonHeader.font fontWithSize:14];
    [bottomBar addSubview:regionButtonHeader];
    
    // Restrict label's height to the actual size
    CGFloat labelHeight = [self getLabelHeight:regionButtonHeader];
    NSLayoutConstraint *labelHeightConstraint = [regionButtonHeader.heightAnchor constraintEqualToConstant:labelHeight];
    [labelHeightConstraint setPriority:999];
    [regionButtonHeader addConstraint:labelHeightConstraint];
    
    
    // Now the button
    regionButton = [[UIButton alloc] init];
    regionButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    CGFloat buttonHeight = 45;
    regionButton.layer.borderColor = [UIColor lightGrayColor].CGColor;
    regionButton.layer.borderWidth = 1.f;
    regionButton.layer.cornerRadius = buttonHeight / 2;
    [regionButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [regionButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateHighlighted];
    regionButton.titleLabel.font = [UIFont systemFontOfSize:regionButton.titleLabel.font.pointSize weight:UIFontWeightLight];
    regionButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
    CGFloat spacing = 10; // the amount of spacing to appear between image and title
    CGFloat spacingFromSides = 10.f;
    
    BOOL isRTL = [self isRightToLeft];
    regionButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, isRTL ? -spacing : spacing);
    regionButton.titleEdgeInsets = UIEdgeInsetsMake(0, isRTL ? -spacing : spacing, 0, 0);
    regionButton.contentEdgeInsets = UIEdgeInsetsMake(0, spacing + spacingFromSides, 0, spacing + spacingFromSides);
    [regionButton addTarget:self action:@selector(onRegionButtonTap:) forControlEvents:UIControlEventTouchUpInside];
    // Set button height
    [regionButton.heightAnchor constraintEqualToConstant:buttonHeight].active = YES;
    [bottomBar addSubview:regionButton];
    [self updateRegionButton];
    [self setRegionSelectionConstraints:self.view.frame.size];
}

- (void)addVersionLabel {
    versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.text = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"APP_VERSION", nil, [NSBundle mainBundle], @"v.%@", @"Text showing the app version. The '%@' placeholder is the version number. So it will look like 'v.2'."),[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    ;
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
    [versionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10].active = YES;
    [versionLabel.centerYAnchor constraintEqualToAnchor:settingsButton.centerYAnchor].active = YES;
    [versionLabel.heightAnchor constraintEqualToConstant:50].active = YES;
}

- (void)addSubscriptionButton {
    subscriptionButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    subscriptionButton.layer.cornerRadius = 20;
    subscriptionButton.clipsToBounds = YES;
    [subscriptionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    subscriptionButton.titleLabel.font = [UIFont boldSystemFontOfSize:subscriptionButton.titleLabel.font.pointSize];
    subscriptionButton.backgroundColor = [[UIColor alloc] initWithRed:42.0/255 green:157.0/255 blue:242.0/255 alpha:1];
    
    subscriptionButton.contentEdgeInsets = UIEdgeInsetsMake(10.0f, 30.0f, 10.0f, 30.0f);
    
    NSString *subscriptionButtonTitle = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_BUTTON_TITLE",
                                                                          nil,
                                                                          [NSBundle mainBundle],
                                                                          @"Go premium now!",
                                                                          @"Text for button that opens paid subscriptions manager UI. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”.");
    [subscriptionButton setTitle:subscriptionButtonTitle forState:UIControlStateNormal];
    [subscriptionButton addTarget:self action:@selector(onSubscriptionTap) forControlEvents:UIControlEventTouchUpInside];
    subscriptionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:subscriptionButton];
    
    // Setup autolayout
    [subscriptionButton.heightAnchor constraintEqualToConstant:40].active = YES;
    [subscriptionButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    NSLayoutConstraint *idealBottomSpacing = [subscriptionButton.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:-10.f];
    [idealBottomSpacing setPriority:999];
    idealBottomSpacing.active = YES;
}

#pragma mark - FeedbackViewControllerDelegate methods and helpers

- (void)userSubmittedFeedback:(NSUInteger)selectedThumbIndex comments:(NSString *)comments email:(NSString *)email uploadDiagnostics:(BOOL)uploadDiagnostics {
    [feedbackManager userSubmittedFeedback:selectedThumbIndex comments:comments email:email uploadDiagnostics:uploadDiagnostics];
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

- (NSArray<NSString*>*)hiddenSpecifierKeys {
    
    VPNStatus s = (VPNStatus) [[self.vpnManager.lastTunnelStatus first] integerValue];
    
    if (s == VPNStatusInvalid ||
        s == VPNStatusDisconnected ||
        s == VPNStatusDisconnecting ) {
        return @[kForceReconnect, kForceReconnectFooter];
    }
    
    return nil;
}

#pragma mark - Psiphon Settings

-(void)notice:(NSString *)noticeJSON {
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
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:appSettingsViewController];
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - Region Selection

- (void)openRegionSelection {
    selectedRegionSnapShot = [[RegionAdapter sharedInstance] getSelectedRegion].code;
    RegionSelectionViewController *regionSelectionViewController = [[RegionSelectionViewController alloc] init];
    regionSelectionNavController = [[UINavigationController alloc] initWithRootViewController:regionSelectionViewController];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"DONE_ACTION", nil, [NSBundle mainBundle], @"Done", @"Title of the button that dismisses region selection dialog")
                                                                   style:UIBarButtonItemStyleDone target:self
                                                                  action:@selector(regionSelectionDidEnd)];
    regionSelectionViewController.navigationItem.rightBarButtonItem = doneButton;
    
    [self presentViewController:regionSelectionNavController animated:YES completion:nil];
}

- (void)regionSelectionDidEnd {
    NSString *selectedRegion = [[RegionAdapter sharedInstance] getSelectedRegion].code;//[[[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_IDENTIFIER] stringForKey:kRegionSelectionSpecifierKey];
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
        if ([AppDelegate isRunningUITest]) {
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
    UIImage *flag = [[PsiphonClientCommonLibraryHelpers imageFromCommonLibraryNamed:selectedRegion.flagResourceId] countryFlag];
    [regionButton setImage:flag forState:UIControlStateNormal];
    
    NSString *regionText = [[RegionAdapter sharedInstance] getLocalizedRegionTitle:selectedRegion.code];
    [regionButton setTitle:regionText forState:UIControlStateNormal];
}

- (void)setRegionSelectionConstraints:(CGSize) size {
    [bottomBar removeConstraints:[bottomBar constraints]];
    if (size.width > size.height && [[UIDevice currentDevice]userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        regionButtonHeader.hidden = YES;
        [regionButton.bottomAnchor constraintEqualToAnchor:bottomBar.bottomAnchor constant:-7].active = YES;
        [regionButton.topAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:7].active = YES;
        [regionButton.centerXAnchor constraintEqualToAnchor:bottomBar.centerXAnchor].active = YES;
        [regionButtonHeader.centerYAnchor constraintEqualToAnchor:regionButton.centerYAnchor].active = YES;
        [regionButtonHeader.trailingAnchor constraintEqualToAnchor:regionButton.leadingAnchor constant:-5.f].active = YES;
    } else {
        regionButtonHeader.hidden = NO;
        [regionButtonHeader.topAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:5].active = YES;
        [regionButtonHeader.centerXAnchor constraintEqualToAnchor:bottomBar.centerXAnchor].active = YES;
        [regionButton.bottomAnchor constraintEqualToAnchor:bottomBar.bottomAnchor constant:-7].active = YES;
        [regionButton.topAnchor constraintEqualToAnchor:regionButtonHeader.bottomAnchor constant:7].active = YES;
        [regionButton.centerXAnchor constraintEqualToAnchor:bottomBar.centerXAnchor].active = YES;

        NSLayoutConstraint *widthConstraint = [regionButton.widthAnchor constraintEqualToAnchor:bottomBar.widthAnchor multiplier:.7f];
        widthConstraint.priority = 999; // allow constraint to be broken to enforce max width
        widthConstraint.active = YES;
        [regionButton.widthAnchor constraintLessThanOrEqualToConstant:220].active = YES;
    }
}

// From https://stackoverflow.com/questions/27374612/how-do-i-calculate-the-uilabel-height-dynamically
- (CGFloat)getLabelHeight:(UILabel*)label {
    CGSize constraint = CGSizeMake(label.frame.size.width, CGFLOAT_MAX);
    CGSize size;
    
    NSStringDrawingContext *context = [[NSStringDrawingContext alloc] init];
    CGSize boundingBox = [label.text boundingRectWithSize:constraint
                                                  options:NSStringDrawingUsesLineFragmentOrigin
                                               attributes:@{NSFontAttributeName:label.font}
                                                  context:context].size;
    
    size = CGSizeMake(ceil(boundingBox.width), ceil(boundingBox.height));
    
    return size.height;
}

- (void)setupLayoutGuides {
    // setup layout equal distribution
    UILayoutGuide *topSpacerGuide = [UILayoutGuide new];
    UILayoutGuide *bottomSpacerGuide = [UILayoutGuide new];
    
    [self.view addLayoutGuide:topSpacerGuide];
    [self.view addLayoutGuide:bottomSpacerGuide];
    
    [topSpacerGuide.heightAnchor constraintGreaterThanOrEqualToConstant:.1].active = YES;
    [bottomSpacerGuide.heightAnchor constraintEqualToAnchor:topSpacerGuide.heightAnchor].active = YES;
    [topSpacerGuide.topAnchor constraintEqualToAnchor:speedBoostMeter.bottomAnchor].active = YES;
    [topSpacerGuide.bottomAnchor constraintEqualToAnchor:startStopButton.topAnchor].active = YES;
    [bottomSpacerGuide.topAnchor constraintEqualToAnchor:statusLabel.bottomAnchor].active = YES;
    
    bottomBarTopConstraint = [bottomSpacerGuide.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor];
    subscriptionButtonTopConstraint = [bottomSpacerGuide.bottomAnchor constraintEqualToAnchor:subscriptionButton.topAnchor];
}

#pragma mark - Subscription

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = NO;
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:iapViewController];
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - PsiCash

#pragma mark - PsiCashPurchaseAlertViewDelegate protocol

- (void)stateBecameStale {
    [alertView close];
    alertView = nil;
}

- (void)showPurchaseAlertView {
    if (alertView != nil) {
        [alertView close];
        alertView = nil;
    }

    if (![model hasAuthPackage] || ![model.authPackage hasSpenderToken]) {
        return;
    } else if ([model hasActiveSpeedBoostPurchase]) {
        alertView = [PsiCashPurchaseAlertView alreadySpeedBoostingAlertWithNMinutesRemaining:[model minutesOfSpeedBoostRemaining]];
    } else  if ([model hasPendingPurchase]) {
        alertView = [PsiCashPurchaseAlertView pendingPurchaseAlert];
    } else {
        alertView = [PsiCashPurchaseAlertView purchaseAlert];
    }

    alertView.controllerDelegate = self;
    [alertView bindWithModel:model];
    [alertView show];
}

- (void)addPsiCashBalanceView {

    // PsiCash balance view
    balanceView = [[PsiCashBalanceView alloc] init];
    balanceView.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:balanceView];

    [balanceView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [balanceView.centerYAnchor constraintEqualToAnchor:settingsButton.centerYAnchor].active = YES;
    [balanceView.widthAnchor constraintEqualToAnchor:subscriptionButton.widthAnchor].active = YES;
    [balanceView.heightAnchor constraintEqualToAnchor:subscriptionButton.heightAnchor].active = YES;

    __weak MainViewController *weakSelf = self;
    balanceViewUpdates = [[PsiCashClient.sharedInstance.clientModelSignal deliverOnMainThread] subscribeNext:^(PsiCashClientModel *newClientModel) {
        __strong MainViewController *strongSelf = weakSelf;
        if (strongSelf != nil) {

            BOOL stateChanged = [model hasActiveSpeedBoostPurchase] ^ [newClientModel hasActiveSpeedBoostPurchase] || [model hasPendingPurchase] ^ [newClientModel hasPendingPurchase];

            model = newClientModel;

            if (stateChanged && alertView != nil) {
                [self showPurchaseAlertView];
            }

            [balanceView bindWithModel:model]; // TODO: don't capture like this
            [speedBoostMeter bindWithModel:model];
        }
    }]; // TODO: dispose

    // Speed Boost Meter
    speedBoostMeter = [[PsiCashSpeedBoostMeterView alloc] init];
    speedBoostMeter.translatesAutoresizingMaskIntoConstraints = NO;

    UITapGestureRecognizer *speedBoostMeterTap = [[UITapGestureRecognizer alloc]
                                                  initWithTarget:self action:@selector(showPurchaseAlertView)];
    speedBoostMeterTap.numberOfTapsRequired = 1;
    [speedBoostMeter addGestureRecognizer:speedBoostMeterTap];

    [self.view addSubview:speedBoostMeter];

    [speedBoostMeter.centerXAnchor constraintEqualToAnchor:balanceView.centerXAnchor].active = YES;
    [speedBoostMeter.topAnchor constraintGreaterThanOrEqualToAnchor:balanceView.bottomAnchor].active = YES;
    NSLayoutConstraint *topSpacing = [speedBoostMeter.topAnchor constraintEqualToAnchor:balanceView.bottomAnchor constant:30.f];
    [topSpacing setPriority:999];
    topSpacing.active = YES;
    [speedBoostMeter.widthAnchor constraintEqualToConstant:300.f].active = YES;
    [speedBoostMeter.heightAnchor constraintEqualToConstant:50].active = YES;
}

#pragma mark - RegionAdapterDelegate protocol implementation

- (void)selectedRegionDisappearedThenSwitchedToBestPerformance {
    dispatch_async_main(^{
        // Alert the user that the VPN failed to start, and that they should try again.
        [UIAlertController presentSimpleAlertWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_FAIL_REGION_INVALID_TITLE", nil, [NSBundle mainBundle], @"Server Region Unavailable", @"Alert dialog title indicating to the user that Psiphon was unable to start because they selected an egress region that is no longer available")
                                               message:NSLocalizedStringWithDefaultValue(@"VPN_START_FAIL_REGION_INVALID_MESSAGE", nil, [NSBundle mainBundle], @"The region you selected is no longer available. You must choose a new region or change to the default \"Best performance\" choice.", @"Alert dialog message informing the user that an error occurred while starting Psiphon because they selected an egress region that is no longer available (Do not translate 'Psiphon'). The user should select a different region and try again. Note: the backslash before each quotation mark should be left as is for formatting.")
                                        preferredStyle:UIAlertControllerStyleAlert
                                             okHandler:nil];
        [self updateRegionButton];
    });
    [self persistSelectedRegion];
    [self.vpnManager stopVPN];
}

@end
