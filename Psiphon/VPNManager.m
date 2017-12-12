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

@property (nonatomic) NETunnelProviderManager *providerManager;

@end

@implementation VPNManager {
    Notifier *notifier;
    PsiphonDataSharedDB *sharedDB;
    id localVPNStatusObserver;
    BOOL restartRequired;
}

@synthesize providerManager = _providerManager;

- (instancetype)init {
    self = [super init];
    if (self) {
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        // Load previous NETunnelProviderManager, if any.
        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:
          ^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
              if ([managers count] == 1) {
                  self.providerManager = managers[0];
              } else if ([managers count] > 1) {
                  LOG_ERROR(@"more than 1 VPN configuration found");
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

#ifdef DEBUG
    if ([AppDelegate isRunningUITest]) {
        return VPNStatusConnected;
    }
#endif

    if (restartRequired) {
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

- (void)startTunnelWithCompletionHandler:(nullable void (^)(NSError * _Nullable error))completionHandler {
    // Override SponsorID if user has active subscription
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

        LOG_DEBUG();

        if (error) {
            // Reset startStopButtonPressed flag to FALSE when error and exiting.
            [self setStartStopButtonPressed:FALSE];
            if (completionHandler) {
                LOG_ERROR(@"Failed to load VPN configuration. Error:%@", error);
                completionHandler([VPNManager errorWithCode:VPNManagerStartErrorLoadConfigsFailed]);
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
            self.providerManager = newManager;

        } else if ([allManagers count] == 1) {
            self.providerManager = allManagers[0];

        } else {
            // Reset startStopButtonPressed flag to FALSE when error and exiting.
            [self setStartStopButtonPressed:FALSE];
            LOG_ERROR(@"%lu VPN configurations found, only expected 1. Aborting", [allManagers count]);
            if (completionHandler) {
                completionHandler([VPNManager errorWithCode:VPNManagerStartErrorTooManyConfigsFounds]);
            }
            return;
        }

        // setEnabled becomes false if the user changes the
        // enabled VPN Configuration from the preferences.
        [self.providerManager setEnabled:TRUE];

       LOG_DEBUG(@"call saveToPreferencesWithCompletionHandler");

        [self.providerManager saveToPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
            if (error != nil) {
                // Reset startStopButtonPressed flag to FALSE when error and exiting.
                [self setStartStopButtonPressed:FALSE];
                // User denied permission to add VPN Configuration.
                LOG_ERROR(@"failed to save the configuration: %@", error);
                if (completionHandler) {
                    completionHandler([VPNManager errorWithCode:VPNManagerStartErrorUserDeniedConfigInstall]);
                }
                return;
            }

            [self.providerManager loadFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                LOG_DEBUG();
                
                // Reset startStopButtonPressed flag to FALSE when it finished loading preferences.
                [self setStartStopButtonPressed:FALSE];
                if (error != nil) {
                    LOG_ERROR(@"Failed to reload VPN configuration. Error:(%@)", error);
                    if (completionHandler) {
                        completionHandler([VPNManager errorWithCode:VPNManagerStartErrorLoadConfigsFailed]);
                    }
                    return;
                }

               LOG_DEBUG(@"Call providerManager.connection.startVPNTunnel()");
                NSError *vpnStartError;
                NSDictionary *extensionOptions = @{EXTENSION_START_FROM_CONTAINER : EXTENSION_START_FROM_CONTAINER_TRUE};

                BOOL vpnStartSuccess = [self.providerManager.connection startVPNTunnelWithOptions:extensionOptions
                                                                                 andReturnError:&vpnStartError];
                if (!vpnStartSuccess) {
                    LOG_ERROR(@"Failed to start network extension. Error:(%@)", vpnStartError);
                    if (completionHandler) {
                        completionHandler([VPNManager errorWithCode:VPNManagerStartErrorNEStartFailed]);
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
    NEVPNStatus s = self.providerManager.connection.status;
    if (s == NEVPNStatusConnecting) {
        [notifier post:@"M.startVPN"];
    } else {
        LOG_WARN(@"Network extension is not in connecting state.");
    }
}

- (void)restartVPNIfActive {
    if (self.providerManager.connection && [self isVPNActive]) {
        restartRequired = YES;
        [self.providerManager.connection stopVPNTunnel];
    }
}


- (void)stopVPN {
    if (self.providerManager.connection) {
        [self.providerManager.connection stopVPNTunnel];
    }
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

- (void)setProviderManager:(NETunnelProviderManager *)providerManager {

    _providerManager = providerManager;
    [self postStatusChangeNotification];

    // Listening to NEVPNManager status change notifications.
    localVPNStatusObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:NEVPNStatusDidChangeNotification
      object:_providerManager.connection queue:NSOperationQueue.mainQueue
      usingBlock:^(NSNotification * _Nonnull note) {

          // Observers of kVPNStatusChangeNotificationName will be notified at the same time.
          [self postStatusChangeNotification];

          // To restart the VPN, should wait till NEVPNStatusDisconnected is received.
          // We can then start a new tunnel.
          // If restartRequired then start  a new network extension process if the previous
          // one has already been disconnected.
          if (_providerManager.connection.status == NEVPNStatusDisconnected && restartRequired) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  [self startTunnelWithCompletionHandler:nil];
              });
          }

      }];
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

- (void)postStatusChangeNotification {
    [[NSNotificationCenter defaultCenter]
      postNotificationName:@kVPNStatusChangeNotificationName object:self];
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
    userInfo[VPNQueryKey] = query;
    if (error) {
        userInfo[NSUnderlyingErrorKey] = error;
    }
    return [[NSError alloc] initWithDomain:VPNQueryErrorDomain code:code userInfo:userInfo];
}

@end
