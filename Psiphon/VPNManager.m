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
#import "AppDelegate.h"
#import "VPNManager.h"
#import "NEBridge.h"
#import "Notifier.h"
#import "Logging.h"
#import "SharedConstants.h"
#import "SettingsViewController.h"
#import "PsiFeedbackLogger.h"

NSNotificationName const VPNManagerStatusDidChangeNotification = @"VPNManagerStatusDidChangeNotification";
NSNotificationName const VPNManagerVPNStartDidFailNotification = @"VPNManagerVPNStartDidFailNotification";

NSErrorDomain const VPNManagerErrorDomain = @"VPNManagerErrorDomain";
NSErrorDomain const VPNQueryErrorDomain = @"VPNQueryErrorDomain";

@interface VPNManager ()

@property (nonatomic, setter=setProviderManager:) NETunnelProviderManager *providerManager;

@property (nonatomic) BOOL restartRequired;

@end

@implementation VPNManager {
    Notifier *notifier;
    id localVPNStatusObserver;

    // Due to the race condition with loading VPN configurations in the init method, and also
    // in the startTunnel method, a dispatch group is used to synchronize this loading behaviour.
    dispatch_group_t initGroup;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        initGroup = dispatch_group_create();

        // Increment number of outstanding tasks in the initGroup due to asynchronous initialization.
        dispatch_group_enter(initGroup);

        __weak VPNManager *weakSelf = self;

        // Load previously saved (if any) VPN configuration.
        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:
          ^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
              if ([managers count] == 1) {

                  // References to `self` should be used with care in the init function.
                  weakSelf.providerManager = managers[0];

                  // If Connect On Demand setting was changed since the last time the app was opened,
                  // reset user's preference to the same state as the VPN Configuration.
                  [[NSUserDefaults standardUserDefaults]
                    setBool:weakSelf.providerManager.isOnDemandEnabled forKey:SettingsConnectOnDemandBoolKey];


              } else if ([managers count] > 1) {
                  [PsiFeedbackLogger error:@"more than 1 VPN configuration found"];
              }

              [weakSelf vpnStatusDidChangeHandler];

              dispatch_group_leave(initGroup);
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

- (VPNStatus)VPNStatus {

    if (!self.providerManager) {
        return VPNStatusInvalid;
    }

#ifdef DEBUG
    if ([AppDelegate isRunningUITest]) {
        return VPNStatusConnected;
    }
#endif

    if (self.restartRequired) {
        // If extension is restarting due to a call to restartVPNIfActive, then
        // we don't want to show the Disconnecting and Disconnected states
        // to the observers, and instead simply notify them that the
        // extension is restarting.
        return VPNStatusRestarting;

    } else {
        switch (self.providerManager.connection.status) {
            case NEVPNStatusInvalid: return VPNStatusInvalid;
            case NEVPNStatusDisconnected: return VPNStatusDisconnected;
            case NEVPNStatusConnecting: return VPNStatusConnecting;
            case NEVPNStatusConnected: return VPNStatusConnected;
            case NEVPNStatusReasserting: return VPNStatusReasserting;
            case NEVPNStatusDisconnecting: return VPNStatusDisconnecting;
        }
    }

    [PsiFeedbackLogger error:@"Unknown NEVPNConnection status: (%ld)", self.providerManager.connection.status];
    return VPNStatusInvalid;
}

- (void)startTunnel {

    if (self.providerManager) {
        NEVPNStatus s = self.providerManager.connection.status;
        if (s != NEVPNStatusInvalid && s != NEVPNStatusDisconnected) {
            LOG_DEBUG(@"Not starting. VPN Status not invalid or disconnected.");
            return;
        }
    }

    // Only one call to startTunnel should be allowed while waiting for the callback chain to finish.
    // tunnelStarting is set to FALSE after the callback chain finishes successfully, or if an error occurs.
    static BOOL tunnelStarting = FALSE;

    if (tunnelStarting) {
        return;
    }
    tunnelStarting = TRUE;

    // Set startStopButtonPressed flag to TRUE
    [self setStartStopButtonPressed:TRUE];

    // Waits until initGroup has no remaining outstanding tasks.
    dispatch_group_notify(initGroup, dispatch_get_main_queue(), ^{
        LOG_DEBUG(@"dispatch block starting");

        self.providerManager = nil;

        // Reset restartRequired flag
        self.restartRequired = FALSE;

        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:
          ^(NSArray<NETunnelProviderManager *> * _Nullable allManagers, NSError * _Nullable error) {

              LOG_DEBUG("Finished loading VPN Configurations.");

              if (error) {
                  // Reset startStopButtonPressed flag to FALSE when error and exiting.
                  [self setStartStopButtonPressed:FALSE];
                  [PsiFeedbackLogger error:@"Failed to load VPN configurations. Error:%@", error];

                  [self postStartFailureNotification:VPNManagerStartErrorConfigLoadFailed];

                  tunnelStarting = FALSE;
                  return;
              }

              NETunnelProviderManager *__providerManager;

              // If there are no configurations, create one
              // if there is more than one, abort!
              if ([allManagers count] == 0) {
                  LOG_WARN(@"No VPN configurations found.");
                  __providerManager = [[NETunnelProviderManager alloc] init];
                  NETunnelProviderProtocol *providerProtocol = [[NETunnelProviderProtocol alloc] init];
                  providerProtocol.providerBundleIdentifier = @"ca.psiphon.Psiphon.PsiphonVPN";
                  __providerManager.protocolConfiguration = providerProtocol;
                  __providerManager.protocolConfiguration.serverAddress = @"localhost";

              } else if ([allManagers count] == 1) {
                  __providerManager = allManagers[0];

              } else {
                  [self setStartStopButtonPressed:FALSE];

                  [PsiFeedbackLogger error:@"%lu VPN configurations found, only expected 1. Deleting all configurations.", [allManagers count]];

                  [self cleanupAllTunnelProviderManagers:allManagers withCompletionHandler:^{
                      [self postStartFailureNotification:VPNManagerStartErrorTooManyConfigsFounds];
                  }];

                  tunnelStarting = FALSE;
                  return;
              }

              // setEnabled becomes false if the user changes the
              // enabled VPN Configuration from the preferences.
              [__providerManager setEnabled:TRUE];
              
              // Adds "always connect" Connect On Demand rule to the configuration.
              if (!__providerManager.onDemandRules || ([__providerManager.onDemandRules count] == 0)) {
                  NEOnDemandRule *connectRule = [NEOnDemandRuleConnect new];
                  [__providerManager setOnDemandRules:@[connectRule]];
              }

              [__providerManager saveToPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                  LOG_DEBUG();

                  if (error != nil) {

                      [self setStartStopButtonPressed:FALSE];

                      // User denied permission to add VPN Configuration.
                      [PsiFeedbackLogger error:@"Failed to save the configuration:%@", error];

                      if (error.code == NEVPNErrorConfigurationInvalid || error.code == NEVPNErrorConfigurationUnknown) {
                          // Fatal errors.
                          [self cleanupAllTunnelProviderManagers:@[__providerManager] withCompletionHandler:^{
                              [self postStartFailureNotification:VPNManagerStartErrorConfigSaveFailed];
                          }];

                      } else {
                          // These errors might be resolved on trying again.
                          [self postStartFailureNotification:VPNManagerStartErrorConfigSaveFailed];
                      }

                      tunnelStarting = FALSE;
                      return;
                  }

                  [__providerManager loadFromPreferencesWithCompletionHandler:^(NSError *error) {

                      if (error != nil) {
                          [PsiFeedbackLogger error:@"Failed to reload VPN configuration. Error:(%@)", error];
                          [self postStartFailureNotification:VPNManagerStartErrorConfigLoadFailed];

                          tunnelStarting = FALSE;
                          return;
                      }

                      self.providerManager = __providerManager;

                      LOG_DEBUG(@"Call providerManager.connection.startVPNTunnel()");
                      NSError *vpnStartError;
                      NSDictionary *extensionOptions = @{EXTENSION_OPTION_START_FROM_CONTAINER: EXTENSION_OPTION_TRUE};

                      BOOL vpnStartSuccess = [self.providerManager.connection startVPNTunnelWithOptions:extensionOptions andReturnError:&vpnStartError];

                      if (!vpnStartSuccess) {
                          [PsiFeedbackLogger error:@"Failed to start network extension. Error:(%@)", vpnStartError];
                          [self postStartFailureNotification:VPNManagerStartErrorNEStartFailed];
                      }

                      LOG_DEBUG(@"Network Extension started successfully.");

                      tunnelStarting = FALSE;
                  }];
              }];
          }];
    });
}

- (void)startVPN {
    dispatch_group_notify(initGroup, dispatch_get_main_queue(), ^{
        NEVPNStatus s = self.providerManager.connection.status;
        if (s == NEVPNStatusConnecting) {
            [notifier post:NOTIFIER_START_VPN];
        } else {
            LOG_WARN(@"Network extension is not in connecting state.");
        }
    });
}

- (void)restartVPNIfActive {
    dispatch_group_notify(initGroup, dispatch_get_main_queue(), ^{
        if (self.providerManager.connection && [self isVPNActive]) {
            self.restartRequired = YES;
            [self.providerManager.connection stopVPNTunnel];
        }
    });
}

- (void)stopVPN {
    dispatch_group_notify(initGroup, dispatch_get_main_queue(), ^{
        if (self.providerManager.connection) {
            [self.providerManager.connection stopVPNTunnel];
        }
    });
}

- (BOOL)isVPNActive {
    VPNStatus s = [self VPNStatus];
    return (s == VPNStatusConnecting || s == VPNStatusConnected || s == VPNStatusReasserting || s == VPNStatusRestarting);
}

- (BOOL)isVPNConnected {
    return VPNStatusConnected == [self VPNStatus];
}

- (BOOL)isOnDemandEnabled {
    return self.providerManager.isOnDemandEnabled;
}

- (void)updateVPNConfigurationOnDemandSetting:(BOOL)onDemandEnabled completionHandler:(void (^)(NSError * _Nullable error))completionHandler {

    // Make sure configuration is not stale by loading again.
    [self.providerManager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
        [self.providerManager setOnDemandEnabled:onDemandEnabled];

        if (onDemandEnabled) {
            // Auto-start VPN on demand has been turned on by the user.
            // To avoid unexpected conflict with other VPN configurations,
            // re-enable Psiphon's VPN configuration.
            [self.providerManager setEnabled:TRUE];
        }
        // Save the updated configuration.
        [self.providerManager saveToPreferencesWithCompletionHandler:^(NSError *error) {
            if (error) {
                [PsiFeedbackLogger error:@"Failed to save VPN configuration. Error: %@", error];
            }
            completionHandler(error);
        }];

    }];
}

#pragma mark - Private network Extension query methods

- (void)isExtensionZombie:(void (^_Nonnull)(BOOL extensionIsZombie))completionHandler {
    [self queryExtension:EXTENSION_QUERY_IS_PROVIDER_ZOMBIE completionHandler:^(NSError *error, NSString *response) {

        if ([error code] == VPNQueryErrorSendFailed) {
            completionHandler(FALSE);
            return;
        }
        
        if ([EXTENSION_RESP_TRUE isEqualToString:response]) {
            completionHandler(TRUE);
        } else if ([EXTENSION_RESP_FALSE isEqualToString:response]) {
            completionHandler(FALSE);
        } else {
            [PsiFeedbackLogger error:@"Unexpected query response (%@). error(%@)", response, error];
            completionHandler(FALSE);
        }
    }];
}

#pragma mark - Public network Extension query methods

- (void)queryNEIsTunnelConnected:(void (^ _Nonnull)(BOOL tunnelIsConnected))completionHandler {
    [self queryExtension:EXTENSION_QUERY_IS_TUNNEL_CONNECTED responseHandler:^(NSError *error, NSString *response) {

        if (error) {
            LOG_WARN(@"query 'isTunnelConnected' failed %@", error);
            completionHandler(FALSE);
            return;
        }
        
        if ([EXTENSION_RESP_TRUE isEqualToString:response]) {
            completionHandler(TRUE);
        } else if ([EXTENSION_RESP_FALSE isEqualToString:response]) {
            completionHandler(FALSE);
        } else {
            [PsiFeedbackLogger error:@"Unexpected query response (%@). error(%@)", response, error];
            completionHandler(FALSE);
        }
    }];
}


#pragma mark - Private methods

- (void)cleanupAllTunnelProviderManagers:(NSArray<NETunnelProviderManager *> *_Nullable)allManagers
                   withCompletionHandler:(void (^_Nonnull)(void))completionHandler {

    // Remove any references to now invalid VPN configurations.
    self.providerManager = nil;

    dispatch_group_t cleanupDispatchGroup = dispatch_group_create();
    for (NETunnelProviderManager *tpm in allManagers) {

        // Increment number of outstanding tasks in initGroup.
        dispatch_group_enter(cleanupDispatchGroup);
        [tpm removeFromPreferencesWithCompletionHandler:^(NSError *error) {
            if (error) {
                [PsiFeedbackLogger error:@"Failed to remove VPN configuration: %@", error];
            }

            dispatch_group_leave(cleanupDispatchGroup);
        }];
    }

    // Waits for all tasks submitted to cleanupDispatchGroup to complete before calling completionHandler.
    dispatch_group_notify(cleanupDispatchGroup, dispatch_get_main_queue(), ^{
        completionHandler();
    });
}

- (void)setProviderManager:(NETunnelProviderManager *)providerManager {

    _providerManager = providerManager;
    if (localVPNStatusObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:localVPNStatusObserver];
    }

    // Post notification status change.
    // NOTE: there may not be an actual status change.
    [self postStatusChangeNotification];

    if (_providerManager) {
        // Listening to NEVPNManager status change notifications.
        localVPNStatusObserver = [[NSNotificationCenter defaultCenter]
          addObserverForName:NEVPNStatusDidChangeNotification
                      object:_providerManager.connection queue:NSOperationQueue.mainQueue
                  usingBlock:^(NSNotification *_Nonnull note) {

                      // Observers of VPNManagerStatusDidChangeNotification will be notified at the same time.
                      [self postStatusChangeNotification];

                      // To restart the VPN, should wait till NEVPNStatusDisconnected is received.
                      // We can then start a new tunnel.
                      // If restartRequired then start  a new network extension process if the previous
                      // one has already been disconnected.
                      if (_providerManager.connection.status == NEVPNStatusDisconnected && self.restartRequired) {
                          dispatch_async(dispatch_get_main_queue(), ^{
                              [self startTunnel];
                          });
                      }
                  }];
    }
}

/**
 * Sends a query to the extension.
 * @param query Query string, typically from SharedConstants.h
 * @param responseHandler Required block that handles the result from the query. If an error occurs,
 *    error object is set with one of VPNQueryErrorCode codes. Otherwise error is nil.
 */
- (void)queryExtension:(NSString *)query responseHandler:(void (^ _Nonnull)(NSError * _Nullable error, NSString * _Nullable response))responseHandler {
    NETunnelProviderSession *session = (NETunnelProviderSession *) self.providerManager.connection;
    NSError *error;
    if (session && [self isVPNActive]) {

        BOOL sent = [session sendProviderMessage:[query dataUsingEncoding:NSUTF8StringEncoding]
                                     returnError:&error
                                 responseHandler:^(NSData *responseData) {
                                     NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                                     LOG_DEBUG(@"Query response (%@)", response);
                                     if (response) {
                                         responseHandler(nil, response);
                                     } else {
                                         responseHandler([VPNManager queryError:query withCode:VPNQueryErrorNilResponse andError:nil], nil);
                                     }
                                 }];

        if (sent) {
            LOG_DEBUG(@"Query (%@) sent to tunnel provider", query);
            return;
        }
    }

    responseHandler([VPNManager queryError:query withCode:VPNQueryErrorSendFailed andError:error], nil);
}

- (void)postStartFailureNotification:(VPNManagerStartErrorCode) error {
    [[NSNotificationCenter defaultCenter] postNotificationName:VPNManagerVPNStartDidFailNotification object:self];
}

- (void)vpnStatusDidChangeHandler {

    // Kill extension if it's a zombie.
    [self isExtensionZombie:^(BOOL isZombie) {
        if (isZombie) {
            LOG_WARN(@"Extension is zombie");
            [self updateVPNConfigurationOnDemandSetting:FALSE completionHandler:^(NSError *error) {
                if (error) {
                    [PsiFeedbackLogger error:@"Failed to disable Connect On Demand. Error: %@", error];
                }
                [self stopVPN];
            }];
        }
    }];

    // To restart the VPN, should wait till NEVPNStatusDisconnected is received.
    // We can then start a new tunnel.
    // If restartRequired then start  a new network extension process if the previous
    // one has already been disconnected.
    if (self.providerManager.connection.status == NEVPNStatusDisconnected && self.restartRequired) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.restartRequired = FALSE;
            [self startTunnel];
        });
    }

    // Since VPN state changes can happen in this block, observers
    // should always be notified at the end of this block.
    [self postStatusChangeNotification];
}

- (void)queryExtension:(NSString *)query completionHandler:(void (^ _Nonnull)(NSError * _Nullable error, NSString * _Nullable response))completionHandler {
    NETunnelProviderSession *session = (NETunnelProviderSession *) self.providerManager.connection;
    if (session && [self isVPNActive]) {
        NSError *err;

        BOOL sent = [session sendProviderMessage:[query dataUsingEncoding:NSUTF8StringEncoding]
                                     returnError:&err
                                 responseHandler:^(NSData *responseData) {
                                     NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                                     LOG_DEBUG(@"Query response (%@)", response);
                                     completionHandler(nil, response);
                                 }];

        if (sent) {
            LOG_DEBUG(@"Query (%@) sent to tunnel provider", query);
        }

        if (err) {
            [PsiFeedbackLogger error:@"Failed to send message to the provider. Error:%@", err];
            completionHandler(err, nil);
        }
    } else {
        completionHandler([VPNManager queryErrorWithCode:VPNQueryErrorSendFailed], nil);
    }
}

- (void)postStatusChangeNotification {
    [[NSNotificationCenter defaultCenter]
      postNotificationName:VPNManagerStatusDidChangeNotification object:self];
}

- (void)dealloc {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:localVPNStatusObserver];
}

#pragma mark - Error conveniece methods

+ (NSError *)errorWithCode:(VPNManagerStartErrorCode)code {
    return [[NSError alloc] initWithDomain:VPNManagerErrorDomain code:code userInfo:nil];
}

+ (NSError *)queryError:(NSString * _Nonnull)query withCode:(VPNQueryErrorCode)code andError:(NSError * _Nullable)error {

    NSString *description;
    switch (code) {
        case VPNQueryErrorSendFailed: description = @"vpn query send failed"; break;
        case VPNQueryErrorNilResponse: description = @"nil response"; break;
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = description;
    userInfo[VPNQueryErrorUserInfoQueryKey] = query;
    if (error) {
        userInfo[NSUnderlyingErrorKey] = error;
    }
    return [[NSError alloc] initWithDomain:VPNQueryErrorDomain code:code userInfo:userInfo];
}

+ (NSError *)queryErrorWithCode:(VPNQueryErrorCode)code {
    return [[NSError alloc] initWithDomain:VPNQueryErrorDomain code:code userInfo:nil];
}

@end
