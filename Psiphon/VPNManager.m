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
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "Logging.h"
#import "NoticeLogger.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "IAPHelper.h"

@interface VPNManager ()

@property (nonatomic, setter=setProviderManager:) NETunnelProviderManager *providerManager;

@property (nonatomic) BOOL restartRequired;

@end

@implementation VPNManager {
    Notifier *notifier;
    PsiphonDataSharedDB *sharedDB;
    id localVPNStatusObserver;

    // Due to the race condition with loading VPN configurations in the init method, and also
    // in the startTunnel method, a dispatch group is used to synchronize this loading behaviour.
    dispatch_group_t initGroup;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        initGroup = dispatch_group_create();

        // Increment number of outstanding tasks in the initGroup due to asynchronous initialization.
        dispatch_group_enter(initGroup);

        // Load previous NETunnelProviderManager, if any.
        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:
          ^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
              if ([managers count] == 1) {
                  self.providerManager = managers[0];
              } else if ([managers count] > 1) {
                  LOG_ERROR(@"more than 1 VPN configuration found");
              }

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

- (VPNStatus)getVPNStatus {

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

    LOG_ERROR(@"Unknown NEVPNConnection status: (%ld)", (long)self.providerManager.connection.status);
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

    // Waits until initGroup has no remaining outstanding tasks.
    dispatch_group_notify(initGroup, dispatch_get_main_queue(), ^{
        LOG_DEBUG(@"dispatch block starting");

        self.providerManager = nil;

        // Override SponsorID if user has active subscription
        if([[IAPHelper sharedInstance] hasActiveSubscriptionForDate:[NSDate date]]) {
            NSString *bundledConfigStr = [PsiphonClientCommonLibraryHelpers getPsiphonBundledConfig];
            if(bundledConfigStr) {
                NSDictionary *config = [PsiphonClientCommonLibraryHelpers jsonToDictionary:bundledConfigStr];
                if (config) {
                    NSDictionary *subscriptionConfig = config[@"subscriptionConfig"];
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
        self.restartRequired = FALSE;

        // Set startStopButtonPressed flag to TRUE
        [self setStartStopButtonPressed:TRUE];

        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:
          ^(NSArray<NETunnelProviderManager *> * _Nullable allManagers, NSError * _Nullable error) {

              LOG_DEBUG("Finished loading VPN Configurations.");

              if (error) {
                  // Reset startStopButtonPressed flag to FALSE when error and exiting.
                  [self setStartStopButtonPressed:FALSE];
                  LOG_ERROR(@"Failed to load VPN configurations. Error:%@", error);

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

                  LOG_ERROR(@"%lu VPN configurations found, only expected 1. Deleting all configurations.", [allManagers count]);

                  [self cleanupAllTunnelProviderManagers:allManagers withCompletionHandler:^{
                      [self postStartFailureNotification:VPNManagerStartErrorTooManyConfigsFounds];
                  }];

                  tunnelStarting = FALSE;
                  return;
              }

              // setEnabled becomes false if the user changes the
              // enabled VPN Configuration from the preferences.
              [__providerManager setEnabled:TRUE];

              [__providerManager saveToPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                  LOG_DEBUG();

                  if (error != nil) {

                      [self setStartStopButtonPressed:FALSE];

                      // User denied permission to add VPN Configuration.
                      LOG_ERROR(@"Failed to save the configuration:%@", error);

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
                          LOG_ERROR(@"Failed to reload VPN configuration. Error:(%@)", error);
                          [self postStartFailureNotification:VPNManagerStartErrorConfigLoadFailed];

                          tunnelStarting = FALSE;
                          return;
                      }

                      self.providerManager = __providerManager;

                      LOG_DEBUG(@"Call providerManager.connection.startVPNTunnel()");
                      NSError *vpnStartError;
                      NSDictionary *extensionOptions = @{EXTENSION_START_FROM_CONTAINER: EXTENSION_START_FROM_CONTAINER_TRUE};

                      BOOL vpnStartSuccess = [self.providerManager.connection startVPNTunnelWithOptions:extensionOptions andReturnError:&vpnStartError];

                      if (!vpnStartSuccess) {
                          LOG_ERROR(@"Failed to start network extension. Error:(%@)", vpnStartError);
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
            [notifier post:@"M.startVPN"];
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
    VPNStatus s = [self getVPNStatus];
    return (s == VPNStatusConnecting || s == VPNStatusConnected || s == VPNStatusReasserting || s == VPNStatusRestarting);
}

- (BOOL)isVPNConnected {
    return VPNStatusConnected == [self getVPNStatus];
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
            LOG_ERROR(@"Unexpected query response (%@)", response);
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
                LOG_ERROR(@"Failed to remove VPN configuration: %@", error);
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

                      // Observers of kVPNStatusChangeNotificationName will be notified at the same time.
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kVPNStartFailure object:self];
}

- (void)postStatusChangeNotification {
    [[NSNotificationCenter defaultCenter]
      postNotificationName:kVPNStatusChangeNotificationName object:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:localVPNStatusObserver];
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

@end
