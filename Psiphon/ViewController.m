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
#import "ViewController.h"
#import "PsiphonData.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "LogViewController.h"
#import "Notifier.h"

@import NetworkExtension;
@import FMDB;


@interface ViewController ()

@property (nonatomic) NEVPNManager *targetManager;

@end

@implementation ViewController {
    PsiphonData *psiphonData;
    PsiphonDataSharedDB *sharedDB;

    // Notifier
    Notifier *notifier;

    // UI elements
    UISwitch *startStopToggle;
    UILabel *toggleLabel;
    UILabel *statusLabel;
}

@synthesize targetManager = _targetManager;

- (id)init {
    self = [super init];
    if (self) {
        self.targetManager = [NEVPNManager sharedManager];
        psiphonData = [PsiphonData sharedInstance];
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        // Notifier
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // TODO: should be abstracted into the PsiphonData singleton?
    // TODO: check if database exists first
    BOOL success = [sharedDB createDatabase];
    if (!success) {
        // TODO : do some error handling
    }

    // Setting up the UI
    [self.view setBackgroundColor:[UIColor whiteColor]];
    //  TODO: wrap this in a function which always
    //  calls them in the right order
    [self addToggleLabel];
    [self addStartAndStopToggle];
    [self addStatusLabel];
    [self addLogViewController];
    
    // Load previous NETunnelProviderManager, if any.
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> * _Nullable managers, NSError * _Nullable error) {
        if (managers == nil) {
            return;
        }
        
        // TODO: should we do error checking here, or on call to startVPN only?
        if ([managers count] == 1) {
            self.targetManager = managers[0];
            [startStopToggle setOn:[self isVPNActive]];
        }
    }];
    
    // TODO: load/save config here to have the user immediately complete the permission prompt
    
    // TODO: perhaps this should be done through the AppDelegate
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Stop watching for status change notifications.
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NEVPNStatusDidChangeNotification object:self.targetManager.connection];
}

- (void)applicationDidBecomeActive {
    // Listen for messages from PacketTunnelProvider (PsiphonVPN)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Get latest persisted logs
        // TODO: truncate logs if extension isn't running
        NSArray<DiagnosticEntry*> *logs = [sharedDB getNewLogs];
        [psiphonData addDiagnosticEntries:logs];

        [self listenForNEMessages];
    });
}

- (void)applicationWillResignActive {
    // Stop listening for diagnostic messages (we don't want to hold the shared db lock while backgrounded)
    // TODO: best place to stop listening for NE messages?
    [notifier stopListeningForAllNotifications];
}

- (void)onSwitch:(UISwitch *)sender {
    if (![self isVPNActive]) {
        [self startVPN];
    } else {
        NSLog(@"call targetManager.connection.stopVPNTunnel()");
        [self.targetManager.connection stopVPNTunnel];
    }
}

- (void)startVPN {
    NSLog(@"startVPN: call loadAllFromPreferencesWithCompletionHandler");
    
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
            NSLog(@"startVPN: %lu VPN configurations found, only expected 1. Aborting", [allManagers count]);
            return;
        }
        
        // setEnabled becomes false if the user changes the
        // enabled VPN Configuration from the prefrences.
        [self.targetManager setEnabled:TRUE];
        
        
        NSLog(@"startVPN: call saveToPreferencesWithCompletionHandler");

        [self.targetManager saveToPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
            if (error != nil) {
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

- (void)listenForNEMessages {

    [notifier listenForNotification:@"NE.newHomepages" listener:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<Homepage *> *homepages = [sharedDB getAllHomepages];
            if ([homepages count] > 0) {
                NSUInteger randIndex = arc4random() % [homepages count];
                Homepage *homepage = homepages[randIndex];

                [[UIApplication sharedApplication] openURL:homepage.url options:@{}
                                         completionHandler:^(BOOL success) {
                                         }];

            }
        });
    }];

    [notifier listenForNotification:@"NE.onConnected" listener:^{
    }];

    [notifier listenForNotification:@"NE.onDiagnosticMessage" listener:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<DiagnosticEntry *> *logs = [sharedDB getNewLogs];
            [psiphonData addDiagnosticEntries:logs];

            #if DEBUG
            for (DiagnosticEntry *log in logs) {
                NSLog(@"%@ %@", [log getTimestampForDisplay], [log message]);
            }
            #endif
        });
    }];
}


# pragma mark - Property getters/setters

- (void)setTargetManager:(NEVPNManager *)targetManager {
    _targetManager = targetManager;
    statusLabel.text = [self getVPNStatusDescription];
    
    // Listening for NEVPNStatusDidChangeNotification
    [[NSNotificationCenter defaultCenter] addObserverForName:NEVPNStatusDidChangeNotification
      object:_targetManager.connection
      queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull note) {
        
        NSLog(@"received NEVPNStatusDidChangeNotification %@", [self getVPNStatusDescription]);

        if (self.targetManager.connection.status == NEVPNStatusConnecting
          || self.targetManager.connection.status == NEVPNStatusDisconnecting) {
            startStopToggle.enabled = FALSE;
        } else {
            startStopToggle.enabled = TRUE;
        }
        statusLabel.text = [self getVPNStatusDescription];
        [startStopToggle setOn:[self isVPNActive]];
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
}

/*!
 @brief Returns true if NEVPNConnectionStatus is Connected, Connecting or Reasserting.
 */
- (BOOL) isVPNActive{
    NEVPNStatus status = self.targetManager.connection.status;
    return (status == NEVPNStatusConnecting
      || status == NEVPNStatusConnected
      || status == NEVPNStatusReasserting);
}

- (void)addLogViewController {
    // Add LogViewController to UIViewController
    LogViewController *controller = [[LogViewController alloc] init];
    controller.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self addChildViewController:controller];
    [self.view addSubview:controller.view];
    [controller didMoveToParentViewController:self];
    
    // Add layout constraints
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:controller.view
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                          toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                          multiplier:1.0
                                                           constant:0.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:controller.view
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:0.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:controller.view
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:statusLabel
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:15.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:controller.view
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:0.0]];
}

- (void)addToggleLabel {
    toggleLabel = [[UILabel alloc] init];
    toggleLabel.text = NSLocalizedString(@"Run Psiphon VPN", @"Label beside toggle button which starts the Psiphon Tunnel");
    toggleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:toggleLabel];
    
    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:toggleLabel
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:15.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:toggleLabel
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.0
                                                           constant:40.0]];
}

- (void)addStartAndStopToggle {
    startStopToggle = [[UISwitch alloc] init];
    startStopToggle.transform = CGAffineTransformMakeScale(1.5, 1.5);
    startStopToggle.translatesAutoresizingMaskIntoConstraints = NO;
    [startStopToggle addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];

    [self.view addSubview:startStopToggle];
    
    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:startStopToggle
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:toggleLabel
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:30.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:startStopToggle
                                                          attribute:NSLayoutAttributeCenterY
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:toggleLabel
                                                          attribute:NSLayoutAttributeCenterY
                                                         multiplier:1.0
                                                           constant:0.0]];
}

- (void)addStatusLabel {
    statusLabel = [[UILabel alloc] init];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.adjustsFontSizeToFitWidth = YES;
    statusLabel.text = @"...";
    [self.view addSubview:statusLabel];
    
    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:statusLabel
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:toggleLabel
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:15.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:statusLabel
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:toggleLabel
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:0.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:statusLabel
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:-15.0]];
}

@end
