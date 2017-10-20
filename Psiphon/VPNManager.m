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

#import <NetworkExtension/NetworkExtension.h>
#import "VPNManager.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "Logging.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "IAPHelper.h"
#import "SettingsViewController.h"

@interface VPNManager ()

@property (nonatomic) NEVPNManager *targetManager;

@end

@implementation VPNManager {
    Notifier *notifier;
    PsiphonDataSharedDB *sharedDB;
    id localVPNStatusObserver;
    BOOL restartRequired;
}

@synthesize targetManager = _targetManager;

- (instancetype)init {
    self = [super init];
    if (self) {
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        self.targetManager = [NEVPNManager sharedManager];

        // Load previously saved (if any) VPN configuration.
        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:
          ^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
              if ([managers count] == 1) {
                  self.targetManager = managers[0];
              }
          }];
    }
    return self;
}

#pragma mark - Public methods

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (VPNStatus)getVPNStatus {
    if (restartRequired) {
        // If extension is restarting due to a call to restartVPN, then
        // we don't want to show the Disconnecting and Disconnected states
        // to the observers, and instead simply notify them that the
        // extension is restarting.
        return VPNStatusRestarting;
    } else {
        switch (self.targetManager.connection.status) {
            case NEVPNStatusInvalid: return VPNStatusInvalid;
            case NEVPNStatusDisconnected: return VPNStatusDisconnected;
            case NEVPNStatusConnecting: return VPNStatusConnecting;
            case NEVPNStatusConnected: return VPNStatusConnected;
            case NEVPNStatusReasserting: return VPNStatusReasserting;
            case NEVPNStatusDisconnecting: return VPNStatusDisconnecting;
        }
    }
    return VPNStatusInvalid;
}

- (void)startTunnelWithCompletionHandler:(nullable void (^)(NSError * _Nullable error))completionHandler {
    // Overide SponsorID if user has active subscrption
    if([[IAPHelper sharedInstance]hasActiveSubscriptionForDate:[NSDate date]]) {
        NSString *bundledConfigStr = [PsiphonClientCommonLibraryHelpers getPsiphonBundledConfig];
        if(bundledConfigStr) {
            NSDictionary *config = [PsiphonClientCommonLibraryHelpers jsonToDictionary:bundledConfigStr];
            if (config) {
                NSDictionary *subscriptionConfig = [config objectForKey:@"subscriptionConfig"];
                if(subscriptionConfig) {
                    [sharedDB updateSponsorId:(NSString*)subscriptionConfig[@"SponsorId"]];
                }
            }
        }
    } else {
        // otherwise delete the entry
        [sharedDB updateSponsorId:nil];
    }

    // Reset restartRequired flag
    restartRequired = FALSE;

    // Set startStopButtonPressed flag to TRUE
    [self setStartStopButtonPressed:TRUE];

    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:
      ^(NSArray<NETunnelProviderManager *> * _Nullable allManagers, NSError * _Nullable error) {

          if (error) {
              // Reset startStopButtonPressed flag to FALSE when error and exiting.
              [self setStartStopButtonPressed:FALSE];
              if (completionHandler) {
                  LOG_ERROR(@"%@", error);
                  completionHandler([VPNManager errorWithCode:VPNManagerErrorLoadConfigsFailed]);
              }
              return;
          }
          
          // If there are no configurations, create one
          // if there is more than one, abort!
          if ([allManagers count] == 0) {
              LOG_WARN(@"No VPN configurations found.");
              NETunnelProviderManager *newManager = [[NETunnelProviderManager alloc] init];
              NETunnelProviderProtocol *providerProtocol = [[NETunnelProviderProtocol alloc] init];
              providerProtocol.providerBundleIdentifier = @"ca.psiphon.Psiphon.PsiphonVPN";
              newManager.protocolConfiguration = providerProtocol;
              newManager.protocolConfiguration.serverAddress = @"localhost";
              self.targetManager = newManager;
          } else if ([allManagers count] > 1) {
              // Reset startStopButtonPressed flag to FALSE when error and exiting.
              [self setStartStopButtonPressed:FALSE];
              LOG_ERROR(@"%lu VPN configurations found, only expected 1. Aborting", (unsigned long)[allManagers count]);
              if (completionHandler) {
                  completionHandler([VPNManager errorWithCode:VPNManagerErrorTooManyConfigsFounds]);
              }
              return;
          }
          
          // Unconditionally sets enabled state of the VPN configuration to TRUE.
          // Enabled state can become FALSE by changing the "enabled" VPN configuration
          // through the iOS settings, or if the user has installed a new VPN configuration.
          [self.targetManager setEnabled:TRUE];

          // Double-checks Connect On Demand enabled state of the VPN configuration,
          // so that it matches user's preferences.
          BOOL onDemandSetting = [[NSUserDefaults standardUserDefaults] boolForKey:kVpnOnDemand];
          [self setTargetManagerOnDemand:onDemandSetting];


          LOG_DEBUG(@"call saveToPreferencesWithCompletionHandler");
          
          [self.targetManager saveToPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
              if (error != nil) {
                  // Reset startStopButtonPressed flag to FALSE when error and exiting.
                  [self setStartStopButtonPressed:FALSE];
                  // User denied permission to add VPN Configuration.
                  LOG_ERROR(@"failed to save the configuration: %@", error);
                  if (completionHandler) {
                      completionHandler([VPNManager errorWithCode:VPNManagerErrorUserDeniedConfigInstall]);
                  }
                  return;
              }
              
              [self.targetManager loadFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                  // Reset startStopButtonPressed flag to FLASE when it finished loading preferences.
                  [self setStartStopButtonPressed:FALSE];
                  if (error != nil) {
                      LOG_ERROR(@"second loadFromPreferences failed");
                      if (completionHandler) {
                          completionHandler([VPNManager errorWithCode:VPNManagerErrorLoadConfigsFailed]);
                      }
                      return;
                  }
                  
                  LOG_DEBUG(@"Call targetManager.connection.startVPNTunnel()");
                  NSError *vpnStartError;
                  NSDictionary *extensionOptions = @{EXTENSION_OPTION_START_FROM_CONTAINER : @YES};
                  
                  BOOL vpnStartSuccess = [self.targetManager.connection startVPNTunnelWithOptions:extensionOptions
                                                                                   andReturnError:&vpnStartError];
                  if (!vpnStartSuccess) {
                      LOG_ERROR(@"startVPNTunnel failed: %@", vpnStartError);
                      if (completionHandler) {
                          completionHandler([VPNManager errorWithCode:VPNManagerErrorNEStartFailed]);
                      }
                      return;
                  }
                  
                  LOG_DEBUG(@"startVPNTunnel success");
                  if (completionHandler) {
                      completionHandler(nil);
                  }
              }];
        }];
    }];
}

- (void)startVPN {
    NEVPNStatus s = self.targetManager.connection.status;
    if (s == NEVPNStatusConnecting) {
        [notifier post:@"M.startVPN"];
    } else {
        LOG_WARN(@"Network extension is not in connecting state.");
    }
}

- (void)restartVPN {
    if (self.targetManager.connection && [self isVPNActive]) {
        restartRequired = YES;
        [self.targetManager.connection stopVPNTunnel];
    }
}

- (void)stopVPN {
    if (self.targetManager.connection) {
        [self.targetManager.connection stopVPNTunnel];
    }
}

- (BOOL)isVPNActive {
    VPNStatus s = [self getVPNStatus];
    return (s == VPNStatusConnecting || s == VPNStatusConnected || s == VPNStatusReasserting || s == VPNStatusRestarting);
}

- (BOOL)isVPNConnected {
    return VPNStatusConnected == [self getVPNStatus];
}

- (BOOL)isTunnelConnected {
    return [self isVPNActive] && [sharedDB getTunnelConnectedState];
}

- (void)updateVPNConfigurationOnDemandSetting {
    if (self.targetManager) {
        BOOL onDemandSetting = [[NSUserDefaults standardUserDefaults] boolForKey:kVpnOnDemand];
        if ([self setTargetManagerOnDemand:onDemandSetting]) {
            // Save the updated configuration.
            [self.targetManager saveToPreferencesWithCompletionHandler:^(NSError *error) {
                if (error) {
                    // TODO: log this error with Notices.
                    LOG_ERROR(@"Failed to save VPN configuration. Error: %@", error);
                }
            }];
        }
    }
}

- (BOOL)isVPNConfigurationInstalled {
    return self.targetManager != nil;
}

- (BOOL)isVPNConfigurationOnDemandEnabled {
    if (self.targetManager) {
        return self.targetManager.isOnDemandEnabled;
    }
    return FALSE;
}

#pragma mark - Helper methods

/*!
 * Sets the VPN configuration On Demand capability.
 * @param enable Whether or not to enable On Demand capability.
 * @return TRUE if VPN configuration was updated, FALSE otherwise.
 */
- (BOOL)setTargetManagerOnDemand:(BOOL)enable {
    if (self.targetManager) {
        if (self.targetManager.isOnDemandEnabled != enable) {
            if (enable) {
                // If set to TRUE, also set the onDemand rules.
                NEOnDemandRule *connectRule = [NEOnDemandRuleConnect new];
                [self.targetManager setOnDemandRules:@[connectRule]];

                LOG_DEBUG(@"TEST number of ondemand rules: %lu", [self.targetManager.onDemandRules count]);
            }
            [self.targetManager setOnDemandEnabled:enable];
            return TRUE;
        }
    }
    return FALSE;
}

#pragma mark - Private methods

- (void)setTargetManager:(NEVPNManager *)targetManager {

    _targetManager = targetManager;
    [self postStatusChangeNotification];

    // Listening to NEVPNManager status change notifications.
    localVPNStatusObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:NEVPNStatusDidChangeNotification
      object:_targetManager.connection queue:NSOperationQueue.mainQueue
      usingBlock:^(NSNotification * _Nonnull note) {

          // Observers of kVPNStatusChangeNotificationName will be notified at the same time.
          [self postStatusChangeNotification];

          // To restart the VPN, should wait till NEVPNStatusDisconnected is received.
          // We can then start a new tunnel.
          // If restartRequired then start  a new network extension process if the previous
          // one has already been disconnected.
          if (_targetManager.connection.status == NEVPNStatusDisconnected && restartRequired) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  [self startTunnelWithCompletionHandler:nil];
              });
          }

      }];
}

- (void)postStatusChangeNotification {
    [[NSNotificationCenter defaultCenter]
      postNotificationName:@kVPNStatusChangeNotificationName object:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:localVPNStatusObserver];
}

+ (NSError *)errorWithCode:(VPNManagerErrorCode)code {
    return [[NSError alloc] initWithDomain:kVPNManagerErrorDomain code:code userInfo:nil];
}

@end
