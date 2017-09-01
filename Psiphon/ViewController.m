
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
#import "FeedbackUpload.h"
#import "LogViewControllerFullScreen.h"
#import "PsiphonConfigUserDefaults.h"
#import "PsiphonClientCommonLibraryConstants.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonDataSharedDB.h"
#import "RegionAdapter.h"
#import "RegionSelectionViewController.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "UIImage+CountryFlag.h"
#import "UpstreamProxySettings.h"
#import "ViewController.h"
#import "VPNManager.h"

static BOOL (^safeStringsEqual)(NSString *, NSString *) = ^BOOL(NSString *a, NSString *b) {
    return (([a length] == 0) && ([b length] == 0)) || ([a isEqualToString:b]);
};

@import NetworkExtension;
@import GoogleMobileAds;

@interface ViewController ()

@property (nonatomic, retain) MPInterstitialAdController *untunneledInterstitial;

@end

@implementation ViewController {

    // VPN Manager
    VPNManager *vpnManager;

    PsiphonDataSharedDB *sharedDB;

    // Notifier
    Notifier *notifier;

    // UI elements
    UIButton *startStopButton;
    UILabel *statusLabel;
    UIButton *regionButton;
    UILabel *regionLabel;
    UILabel *versionLabel;
    UILabel *adLabel;

    // App state variables
    BOOL shownHomepage;
    BOOL adWillShow;     // Ad will show soon.

    // UI Constraint
    NSLayoutConstraint *startButtonScreenWidth;
    NSLayoutConstraint *startButtonScreenHeight;
    NSLayoutConstraint *startButtonWidth;

    // VPN Config user defaults
    PsiphonConfigUserDefaults *psiphonConfigUserDefaults;

    // Settings
    PsiphonSettingsViewController *appSettingsViewController;

    // Region Selection
    UINavigationController *regionSelectionNavController;
    NSString *selectedRegionSnapShot;
}

- (id)init {
    self = [super init];
    if (self) {
        vpnManager = [[VPNManager alloc] init];

        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        // Notifier
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        // VPN Config user defaults
        psiphonConfigUserDefaults = [PsiphonConfigUserDefaults sharedInstance];
        [self persistSettingsToSharedUserDefaults];

        // State variables
        [self resetAppState];
    }
    return self;
}

// Initializes/resets variables that track application state
- (void)resetAppState {
    shownHomepage = FALSE;
    adWillShow = FALSE;
}

#pragma mark - Lifecycle methods

- (void)viewDidLoad {
    [super viewDidLoad];

    // TODO: check if database exists first
    BOOL success = [sharedDB createDatabase];
    if (!success) {
        // TODO : do some error handling
    }

    // Add any available regions from shared db to region adapter
    [self updateAvailableRegions];

    // Setting up the UI
    [self.view setBackgroundColor:[UIColor whiteColor]];
    //  TODO: wrap this in a function which always
    //  calls them in the right order
    [self addSettingsButton];
    [self addStartAndStopButton];
    [self addStatusLabel];
    [self addRegionButton];
    [self addRegionLabel];
    [self addAdLabel];
    [self addVersionLabel];

    // TODO: load/save config here to have the user immediately complete the permission prompt

    // TODO: perhaps this should be done through the AppDelegate
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Available regions may have changed in the background
    [self updateAvailableRegions];
    [self updateRegionButton];
    [self updateRegionLabel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [[NSNotificationCenter defaultCenter]
      addObserver:self selector:@selector(vpnStatusDidChange) name:@kVPNStatusChange object:vpnManager];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)applicationDidBecomeActive {
    // Listen for messages from Network Extension
    [self listenForNEMessages];

    [sharedDB updateAppForegroundState:YES];
}

- (void)applicationWillResignActive {

    [sharedDB updateAppForegroundState:NO];

    // Stop listening for diagnostic messages (we don't want to hold the shared db lock while backgrounded)
    // TODO: best place to stop listening for NE messages?
    [notifier stopListeningForAllNotifications];
}

// Reload when rotate
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [self.view removeConstraint:startButtonWidth];

    if (size.width > size.height) {
        [self.view removeConstraint:startButtonScreenWidth];
        [self.view addConstraint:startButtonScreenHeight];
    } else {
        [self.view removeConstraint:startButtonScreenHeight];
        [self.view addConstraint:startButtonScreenWidth];
    }

    [self.view addConstraint:startButtonWidth];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    }];

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

#pragma mark - UI callbacks

- (void)vpnStatusDidChange {
    // Update UI
    startStopButton.selected = [vpnManager isVPNActive];
    statusLabel.text = [self getVPNStatusDescription:[vpnManager getVPNStatus]];

    if ([vpnManager getVPNStatus] == VPNStatusDisconnected) {
        // The VPN is stopped. Initialize ads after a delay:
        //    - to ensure regular untunneled networking is ready
        //    - because it's likely the user will be leaving the app, so we don't want to request
        //      another ad right away
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self initializeAds];
        });
    } else {
        [self initializeAds];
    }
}

- (void)onStartStopTap:(UIButton *)sender {
    if (![vpnManager isVPNActive]) {
        [self showUntunneledInterstitial];
    } else {
        NSLog(@"call targetManager.connection.stopVPNTunnel()");
        [vpnManager stopVPN];
    }
}

- (void)onSettingsButtonTap:(UIButton *)sender {
    [self openSettingsMenu];
}

- (void)onRegionButtonTap:(UIButton *)sender {
    [self openRegionSelection];
}

- (void)onVersionLabelTap:(UILabel *)sender {
    LogViewControllerFullScreen *log = [[LogViewControllerFullScreen alloc] init];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:log];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    [self presentViewController:nav animated:YES completion:nil];
}

- (void)onAdClick:(UIButton *)sender {
    [self showUntunneledInterstitial];
}

# pragma mark - Network Extension

- (void)listenForNEMessages {
    [notifier listenForNotification:@"NE.newHomepages" listener:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (!shownHomepage) {
                NSArray<Homepage *> *homepages = [sharedDB getAllHomepages];
                if ([homepages count] > 0) {
                    NSUInteger randIndex = arc4random() % [homepages count];
                    Homepage *homepage = homepages[randIndex];

                    [[UIApplication sharedApplication] openURL:homepage.url options:@{}
                                             completionHandler:^(BOOL success) {
                                                 shownHomepage = success;
                                             }];

                }
            }
        });
    }];

    [notifier listenForNotification:@"NE.tunnelConnected" listener:^{
        // If we haven't had a chance to load an Ad, and the
        // tunnel is already connected, give up on the Ad and
        // start the VPN. Otherwise the startVPN message will be
        // sent after the Ad has disappeared.
        if (!adWillShow) {
            [vpnManager startVPN];
        }
    }];

    [notifier listenForNotification:@"NE.onAvailableEgressRegions" listener:^{ // TODO should be put in a constants file
        [self updateAvailableRegions];
    }];
}

# pragma mark - UI helper functions

- (NSString *)getVPNStatusDescription:(VPNStatus) status {
    switch(status) {
        case VPNStatusDisconnected: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_DISCONNECTED", nil, [NSBundle mainBundle], @"Disconnected", @"Status when the VPN is not connected to a Psiphon server, not trying to connect, and not in an error state");
        case VPNStatusInvalid: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_INVALID", nil, [NSBundle mainBundle], @"Invalid", @"Status when the VPN is in an invalid state. For example, if the user doesn't give permission for the VPN configuration to be installed, and therefore the Psiphon VPN can't even try to connect.");
        case VPNStatusConnected: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_CONNECTED", nil, [NSBundle mainBundle], @"Connected", @"Status when the VPN is connected to a Psiphon server");
        case VPNStatusConnecting: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_CONNECTING", nil, [NSBundle mainBundle], @"Connecting", @"Status when the VPN is connecting; that is, trying to connect to a Psiphon server");
        case VPNStatusDisconnecting: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_DISCONNECTING", nil, [NSBundle mainBundle], @"Disconnecting", @"Status when the VPN is disconnecting. Sometimes going from connected to disconnected can take some time, and this is that state.");
        case VPNStatusReasserting: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_RECONNECTING", nil, [NSBundle mainBundle], @"Reconnecting", @"Status when the VPN was connected to a Psiphon server, got disconnected unexpectedly, and is currently trying to reconnect");
        case VPNStatusRestarting: return NSLocalizedStringWithDefaultValue(@"VPN_STATUS_RESTARTING", nil, [NSBundle mainBundle], @"Restarting", @"Status when the VPN is restarting.");
    }
    return nil;
}

- (void)addSettingsButton {
    UIButton *settingsButton = [[UIButton alloc] init];
    settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [settingsButton setImage:[UIImage imageNamed:@"settings"] forState:UIControlStateNormal];
    [self.view addSubview:settingsButton];

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:settingsButton
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.topLayoutGuide
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:-5]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:settingsButton
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:-5]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:settingsButton
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:nil
                                                          attribute:NSLayoutAttributeNotAnAttribute
                                                         multiplier:1.0
                                                           constant:40]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:settingsButton
                                                          attribute:NSLayoutAttributeHeight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:settingsButton
                                                          attribute:NSLayoutAttributeWidth
                                                         multiplier:1.0
                                                           constant:0.f]];

    [settingsButton addTarget:self action:@selector(onSettingsButtonTap:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)addStartAndStopButton {
    UIImage *stopButtonImage = [UIImage imageNamed:@"StopButton"];
    UIImage *startButtonImage = [UIImage imageNamed:@"StartButton"];

    startStopButton = [UIButton buttonWithType:UIButtonTypeCustom];
    startStopButton.translatesAutoresizingMaskIntoConstraints = NO;
    startStopButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    startStopButton.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;

    [startStopButton setImage:startButtonImage forState:UIControlStateNormal];
    [startStopButton setImage:stopButtonImage forState:UIControlStateSelected];

    [startStopButton addTarget:self action:@selector(onStartStopTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:startStopButton];

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:startStopButton
                                                          attribute:NSLayoutAttributeCenterY
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeCenterY
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:startStopButton
                                                          attribute:NSLayoutAttributeCenterX
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeCenterX
                                                         multiplier:1.0
                                                           constant:0]];

    startButtonScreenHeight = [NSLayoutConstraint constraintWithItem:startStopButton
                                                           attribute:NSLayoutAttributeHeight
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:self.view
                                                           attribute:NSLayoutAttributeHeight
                                                          multiplier:0.5f
                                                            constant:0];

    startButtonScreenWidth = [NSLayoutConstraint constraintWithItem:startStopButton
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeWidth
                                                         multiplier:0.5f
                                                           constant:0];

    startButtonWidth = [NSLayoutConstraint constraintWithItem:startStopButton
                                                    attribute:NSLayoutAttributeHeight
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:startStopButton
                                                    attribute:NSLayoutAttributeWidth
                                                   multiplier:1.0
                                                     constant:0];

    CGSize viewSize = self.view.bounds.size;

    if (viewSize.width > viewSize.height) {
        [self.view addConstraint:startButtonScreenHeight];
    } else {
        [self.view addConstraint:startButtonScreenWidth];
    }

    [self.view addConstraint:startButtonWidth];
}

- (void)addStatusLabel {
    statusLabel = [[UILabel alloc] init];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.adjustsFontSizeToFitWidth = YES;
    statusLabel.text = @"...";
    statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:statusLabel];

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:statusLabel
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                             toItem:startStopButton
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.0
                                                           constant:-30.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:statusLabel
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:15.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:statusLabel
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:-15.0]];
}

- (void)addRegionButton {
    regionButton = [[UIButton alloc] init];
    regionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [regionButton addTarget:self action:@selector(onRegionButtonTap:) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:regionButton];

    [self updateRegionButton];

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:regionButton
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationLessThanOrEqual
                                                             toItem:startStopButton
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:30.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:regionButton
                                                          attribute:NSLayoutAttributeCenterX
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeCenterX
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:regionButton
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeWidth
                                                         multiplier:1.0
                                                           constant:.2]];
}

- (void)addRegionLabel {
    regionLabel = [[UILabel alloc] init];
    regionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    regionLabel.adjustsFontSizeToFitWidth = YES;
    regionLabel.numberOfLines = 0;
    regionLabel.textAlignment = NSTextAlignmentCenter;
    regionLabel.font = [UIFont systemFontOfSize:15.f];
    [self.view addSubview:regionLabel];

    [self updateRegionLabel];

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:regionLabel
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:regionButton
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:5.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:regionLabel
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationLessThanOrEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:0.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:regionLabel
                                                          attribute:NSLayoutAttributeCenterX
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:regionButton
                                                          attribute:NSLayoutAttributeCenterX
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:regionLabel
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeWidth
                                                         multiplier:1.0
                                                           constant:.1]];
}

- (void)addVersionLabel {
    versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.text = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"APP_VERSION", nil, [NSBundle mainBundle], @"Version %@", @"Text showing the app version. The '%@' placeholder is the version number. So it will look like 'Version 2'."),[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    ;
    versionLabel.userInteractionEnabled = YES;

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc]
      initWithTarget:self action:@selector(onVersionLabelTap:)];
    tapRecognizer.numberOfTapsRequired = 2;
    [versionLabel addGestureRecognizer:tapRecognizer];

    [self.view addSubview:versionLabel];

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:versionLabel
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                          constant:-30.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:versionLabel
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:-30.0]];
}

- (void)addAdLabel {
    adLabel = [[UILabel alloc] init];
    adLabel.translatesAutoresizingMaskIntoConstraints = NO;
    adLabel.text = NSLocalizedStringWithDefaultValue(@"AD_LOADED", nil, [NSBundle mainBundle], @"Ad Loaded", @"Text for button that plays the main screen ad");
    adLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:adLabel];
    adLabel.hidden = true;

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:adLabel
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                             toItem:self.topLayoutGuide
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:adLabel
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:statusLabel
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.0
                                                           constant:-20.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:adLabel
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:15.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:adLabel
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:-15.0]];
}

# pragma mark - Ads

- (void)initializeAds {
    NSLog(@"initializeAds");
    if ([vpnManager isVPNActive]) {
        adLabel.hidden = true;
    } else if ([vpnManager getVPNStatus] == VPNStatusDisconnected) {
        [GADMobileAds configureWithApplicationID:@"ca-app-pub-1072041961750291~2085686375"];
        [self loadUntunneledInterstitial];
    }
}

- (bool)shouldShowUntunneledAds {
    return [vpnManager getVPNStatus] == VPNStatusDisconnected;
}

- (void)loadUntunneledInterstitial {
    NSLog(@"loadUntunneledInterstitial");
    self.untunneledInterstitial = [MPInterstitialAdController
      interstitialAdControllerForAdUnitId:@"4250ebf7b28043e08ddbe04d444d79e4"];
    self.untunneledInterstitial.delegate = self;
    [self.untunneledInterstitial loadAd];
}

- (void)showUntunneledInterstitial {
    NSLog(@"showUntunneledInterstitial");
    if (self.untunneledInterstitial.ready) {
        adWillShow = YES;
        [self.untunneledInterstitial showFromViewController:self];
    }

    // Start the tunnel in parallel with showing ads.
    // VPN won't start until [vpnManager startVPN] message is sent.
    [vpnManager startTunnelWithCompletionHandler:^(BOOL success) {
        // TODO:
    }];
}

- (void)interstitialDidLoadAd:(MPInterstitialAdController *)interstitial {
    NSLog(@"Interstitial loaded");
    adLabel.hidden = false;
}

- (void)interstitialDidFailToLoadAd:(MPInterstitialAdController *)interstitial {
    NSLog(@"Interstitial failed to load");
    // Don't retry.
}

- (void)interstitialDidExpire:(MPInterstitialAdController *)interstitial {
    NSLog(@"Interstitial expired");
    adLabel.hidden = true;
    [interstitial loadAd];
}

- (void)interstitialDidDisappear:(MPInterstitialAdController *)interstitial {
    NSLog(@"Interstitial dismissed");
    // TODO: start the tunnel? or set a flag indicating that the tunnel should be started when returning to the UI?
    adLabel.hidden = true;

    adWillShow = NO;

    // Post message to the extension to start the VPN
    // when the tunnel is established.
    [vpnManager startVPN];
}

#pragma mark - FeedbackViewControllerDelegate methods and helpers

- (NSString *)getPsiphonConfig {
    return [PsiphonClientCommonLibraryHelpers getPsiphonConfigForFeedbackUpload];
}

- (void)userSubmittedFeedback:(NSUInteger)selectedThumbIndex comments:(NSString *)comments email:(NSString *)email uploadDiagnostics:(BOOL)uploadDiagnostics {
    // Ensure psiphon data is populated with latest logs
    // TODO: should this be a delegate method of Psiphon Data in shared library/
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<DiagnosticEntry *> *logs = [sharedDB getNewLogs];
        [[PsiphonData sharedInstance] addDiagnosticEntries:logs];
    });

    __weak ViewController *weakSelf = self;
    SendFeedbackHandler sendFeedbackHandler = ^(NSString *jsonString, NSString *pubKey, NSString *uploadServer, NSString *uploadServerHeaders){
        PsiphonTunnel *inactiveTunnel = [PsiphonTunnel newPsiphonTunnel:self]; // TODO: we need to update PsiphonTunnel framework not require this and fix this warning
        [inactiveTunnel sendFeedback:jsonString publicKey:pubKey uploadServer:uploadServer uploadServerHeaders:uploadServerHeaders];
    };

    [FeedbackUpload generateAndSendFeedback:selectedThumbIndex
                                   comments:comments
                                      email:email
                         sendDiagnosticInfo:uploadDiagnostics
                          withPsiphonConfig:[self getPsiphonConfig]
                         withConnectionType:[self getConnectionType]
                               isJailbroken:[JailbreakCheck isDeviceJailbroken]
                        sendFeedbackHandler:sendFeedbackHandler];
}

- (void)userPressedURL:(NSURL *)URL {
    [[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:nil];
}

// Get connection type for feedback
- (NSString*)getConnectionType {

    Reachability *reachability = [Reachability reachabilityForInternetConnection];

    NetworkStatus status = [reachability currentReachabilityStatus];

    if(status == NotReachable)
    {
        return @"none";
    }
    else if (status == ReachableViaWiFi)
    {
        return @"WIFI";
    }
    else if (status == ReachableViaWWAN)
    {
        return @"mobile";
    }

    return @"error";
}

#pragma mark - PsiphonSettingsViewControllerDelegate methods and helpers

- (void)notifyPsiphonConnectionState {
    // Unused
}

- (void)reloadAndOpenSettings {
    if (appSettingsViewController != nil) {
        __weak ViewController *weakSelf = self;
        [appSettingsViewController dismissViewControllerAnimated:NO completion:^{
            [[RegionAdapter sharedInstance] reloadTitlesForNewLocalization];
            [weakSelf openSettingsMenu];
        }];
    }
}

- (void)settingsWillDismissWithForceReconnect:(BOOL)forceReconnect {
    if (forceReconnect) {
        [self persistSettingsToSharedUserDefaults];
        [vpnManager restartVPN];
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
    NSString *upstreamProxyUrl = [[UpstreamProxySettings sharedInstance] getUpstreamProxyUrl];
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_IDENTIFIER];
    [userDefaults setObject:upstreamProxyUrl forKey:PSIPHON_CONFIG_UPSTREAM_PROXY_URL];
}

- (BOOL)shouldEnableSettingsLinks {
    return YES;
}

#pragma mark - Psiphon Settings

- (void)openSettingsMenu {
    appSettingsViewController = [[PsiphonSettingsViewController alloc] init];
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
        [self updateRegionLabel];
        [vpnManager restartVPN];
    }
    [regionSelectionNavController dismissViewControllerAnimated:YES completion:nil];
    regionSelectionNavController = nil;
}

- (void)updateAvailableRegions {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSString *> *regions = [sharedDB getAllEgressRegions];
        [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
    });
}

- (void)updateRegionButton {
    Region *selectedRegion = [[RegionAdapter sharedInstance] getSelectedRegion];
    UIImage *flag = [[PsiphonClientCommonLibraryHelpers imageFromCommonLibraryNamed:selectedRegion.flagResourceId] countryFlag];
    [regionButton setImage:flag forState:UIControlStateNormal];
}

- (void)updateRegionLabel {
    Region *selectedRegion = [[RegionAdapter sharedInstance] getSelectedRegion];
    NSString *serverRegionText = NSLocalizedStringWithDefaultValue(@"SERVER_REGION", nil, [NSBundle mainBundle], @"Server region", @"Title which is displayed beside the flag of the country which the user has chosen to connect to.");
    NSString *regionText = [[RegionAdapter sharedInstance] getLocalizedRegionTitle:selectedRegion.code];
    regionLabel.text = [serverRegionText stringByAppendingString:[NSString stringWithFormat:@":\n%@", regionText]];
}

@end
