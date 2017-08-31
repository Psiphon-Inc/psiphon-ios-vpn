
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

static BOOL (^safeStringsEqual)(NSString *, NSString *) = ^BOOL(NSString *a, NSString *b) {
    return (([a length] == 0) && ([b length] == 0)) || ([a isEqualToString:b]);
};

@import NetworkExtension;
@import GoogleMobileAds;


@interface ViewController ()

@property (nonatomic) NEVPNManager *targetManager;
@property (nonatomic, retain) MPInterstitialAdController *untunneledInterstitial;

@end

@implementation ViewController {

    PsiphonDataSharedDB *sharedDB;

    // Notifier
    Notifier *notifier;

    // UI elements
    UISwitch *startStopToggle;
    UIButton *startStopButton;
    UILabel *toggleLabel;
    UILabel *statusLabel;
    UIButton *regionButton;
    UILabel *versionLabel;
    UILabel *adLabel;

    // App state variables
    BOOL shownHomepage;
    BOOL restartRequired;
    BOOL canStartTunnel;
    
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

@synthesize targetManager = _targetManager;

- (id)init {
    self = [super init];
    if (self) {
        self.targetManager = [NEVPNManager sharedManager];

        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        
        // Notifier
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        // VPN Config user defaults
        psiphonConfigUserDefaults = [PsiphonConfigUserDefaults sharedInstance];
        [self persistSettingsToSharedUserDefaults];

        [self resetAppState];
    }
    return self;
}

// Initializes/resets variables that track application state
- (void)resetAppState {
    shownHomepage = FALSE;
    restartRequired = FALSE;
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
    [self addAdLabel];
    [self addVersionLabel];
    
    // Load previous NETunnelProviderManager, if any.
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> * _Nullable managers, NSError * _Nullable error) {
        if (managers == nil) {
            return;
        }
        
        // TODO: should we do error checking here, or on call to startVPN only?
        if ([managers count] == 1) {
            self.targetManager = managers[0];
            if ([self isVPNActive]){
                startStopButton.selected = YES;
            } else {
                startStopButton.selected = NO;
            }
            [self initializeAds];
        }
    }];
    
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
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Stop watching for status change notifications.
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NEVPNStatusDidChangeNotification object:self.targetManager.connection];
}

- (void)applicationDidBecomeActive {
    // Listen for messages from Network Extension
    [self listenForNEMessages];
}

- (void)applicationWillResignActive {
    // Stop listening for diagnostic messages (we don't want to hold the shared db lock while backgrounded)
    // TODO: best place to stop listening for NE messages?
    [notifier stopListeningForAllNotifications];
}

// Reload when rotate
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
         [self.view removeConstraint:startButtonWidth];
         CGSize viewSize = self.view.bounds.size;
         
         if (viewSize.width > viewSize.height) {
             [self.view removeConstraint:startButtonScreenWidth];
             [self.view addConstraint:startButtonScreenHeight];
         } else {
             [self.view removeConstraint:startButtonScreenHeight];
             [self.view addConstraint:startButtonScreenWidth];
         }
         
         [self.view addConstraint:startButtonWidth];
     }];
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

#pragma mark - UI callbacks

- (void)onStartStopTap:(UIButton *)sender {
    if (![self isVPNActive]) {
        [self showUntunneledInterstitial];
        // Then Start VPN
    } else {
        NSLog(@"call targetManager.connection.stopVPNTunnel()");
        [self.targetManager.connection stopVPNTunnel];
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

- (void)startVPN {
    NSLog(@"startVPN: call loadAllFromPreferencesWithCompletionHandler");

    [self resetAppState];

    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> * _Nullable allManagers, NSError * _Nullable error) {
        
        if (allManagers == nil) {
            return;
        }
        
        // If there are no configurations, create one
        // if there is more than one, abort!
        if ([allManagers count] == 0) {
            NSLog(@"startVPN: np VPN configurations found");
            NETunnelProviderManager *newManager = [[NETunnelProviderManager alloc] init];
            NETunnelProviderProtocol *providerProtocol = [[NETunnelProviderProtocol alloc] init];
            providerProtocol.providerBundleIdentifier = @"ca.psiphon.Psiphon.PsiphonVPN";
            newManager.protocolConfiguration = providerProtocol;
            newManager.protocolConfiguration.serverAddress = @"localhost";
            self.targetManager = newManager;
        } else if ([allManagers count] > 1) {
            NSLog(@"startVPN: %lu VPN configurations found, only expected 1. Aborting", (unsigned long)[allManagers count]);
            return;
        }
        
        // setEnabled becomes false if the user changes the
        // enabled VPN Configuration from the prefrences.
        [self.targetManager setEnabled:TRUE];
        
        
        NSLog(@"startVPN: call saveToPreferencesWithCompletionHandler");

        [self.targetManager saveToPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
            if (error != nil) {
                // User denied permission to add VPN Configuration.
                startStopButton.selected = NO;
                NSLog(@"startVPN: failed to save the configuration: %@", error);
                return;
            }
            
            [self.targetManager loadFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                if (error != nil) {
                    NSLog(@"startVPN: second loadFromPreferences failed");
                    return;
                }

                NSLog(@"startVPN: call targetManager.connection.startVPNTunnel()");
                NSError *vpnStartError;
                NSDictionary *extensionOptions = @{EXTENSION_OPTION_START_FROM_CONTAINER : @YES};

                BOOL vpnStartSuccess = [self.targetManager.connection startVPNTunnelWithOptions:extensionOptions
                  andReturnError:&vpnStartError];
                if (!vpnStartSuccess) {
                    NSLog(@"startVPN: startVPNTunnel failed: %@", vpnStartError);
                }
                
                NSLog(@"startVPN: startVPNTunnel success");
            }];
        }];
    }];
}

- (void)restartVPN {
    if (self.targetManager.connection) {
        restartRequired = TRUE;
        [self.targetManager.connection stopVPNTunnel];
    }
}

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

    [notifier listenForNotification:@"NE.onConnected" listener:^{
    }];

    [notifier listenForNotification:@"NE.onAvailableEgressRegions" listener:^{ // TODO should be put in a constants file
        [self updateAvailableRegions];
    }];
}

# pragma mark - Property getters/setters

- (void)setTargetManager:(NEVPNManager *)targetManager {
    _targetManager = targetManager;
    statusLabel.text = [self getVPNStatusDescription];
    
    // Listening for NEVPNStatusDidChangeNotification
    [[NSNotificationCenter defaultCenter] addObserverForName:NEVPNStatusDidChangeNotification
      object:_targetManager.connection queue:NSOperationQueue.mainQueue
      usingBlock:^(NSNotification * _Nonnull note) {

          if (_targetManager.connection.status == NEVPNStatusDisconnected) {
              if (restartRequired) {
                  restartRequired = FALSE;
                  dispatch_async(dispatch_get_main_queue(), ^{
                      [self startVPN];
                  });
              } else {
                  // The VPN is stopped. Initialize ads after a delay:
                  //    - to ensure regular untunneled networking is ready
                  //    - because it's likely the user will be leaving the app, so we don't want to request
                  //      another ad right away
                  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                      [self initializeAds];
                  });
              }
          } else {
              [self initializeAds];
          }

          NSLog(@"received NEVPNStatusDidChangeNotification %@", [self getVPNStatusDescription]);
          statusLabel.text = [self getVPNStatusDescription];
          if ([self isVPNActive]){
              startStopButton.selected = YES;
          } else {
              startStopButton.selected = NO;
          }
    }];
}


# pragma mark - UI helper functions

/*!
 @brief Returns targetManager current connection status description.
 */
- (NSString *)getVPNStatusDescription {
    switch(self.targetManager.connection.status) {
        case NEVPNStatusDisconnected: return @"Disconnected";
        case NEVPNStatusInvalid: return @"Invalid";
        case NEVPNStatusConnected: return @"Connected";
        case NEVPNStatusConnecting: return @"Connecting";
        case NEVPNStatusDisconnecting: return @"Disconnecting";
        case NEVPNStatusReasserting: return @"Reconnecting";
    }
    return nil;
}

/*!
 @brief Returns true if NEVPNConnectionStatus is Connected, Connecting or Reasserting.
 */
- (BOOL)isVPNActive {
    NEVPNStatus status = self.targetManager.connection.status;
    return (status == NEVPNStatusConnecting
      || status == NEVPNStatusConnected
      || status == NEVPNStatusReasserting);
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
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:settingsButton
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:settingsButton
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:nil
                                                          attribute:NSLayoutAttributeNotAnAttribute
                                                         multiplier:1.0
                                                           constant:60]];

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
                                                          relatedBy:NSLayoutRelationEqual
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
                                                          relatedBy:NSLayoutRelationEqual
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
                                                           constant:15.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:regionButton
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeWidth
                                                         multiplier:1.0
                                                           constant:.2]];
}

- (void)addVersionLabel {
    versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.text = [NSString stringWithFormat:@"Version %@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
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
    adLabel.text = @"Ad Loaded";
    adLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:adLabel];
    adLabel.hidden = true;

    // Setup autolayout
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
    if ([self isVPNActive]) {
        adLabel.hidden = true;
    } else if (self.targetManager.connection.status == NEVPNStatusDisconnected && !restartRequired) {
        [GADMobileAds configureWithApplicationID:@"ca-app-pub-1072041961750291~2085686375"];
        [self loadUntunneledInterstitial];
    }
}

- (bool)shouldShowUntunneledAds {
    return self.targetManager.connection.status == NEVPNStatusDisconnected && !restartRequired;
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
        [self.untunneledInterstitial showFromViewController:self];
    }else{
        [self startVPN];
    }
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
    [self startVPN];
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
        [self restartVPN];
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
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Done", @"Title of the button that dismisses region selection dialog")
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
        [self restartVPN];
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

@end
