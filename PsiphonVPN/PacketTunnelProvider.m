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

#import <PsiphonTunnel/PsiphonTunnel.h>
#import "TunnelFileDescriptor.h"
#import <NetworkExtension/NEPacketTunnelNetworkSettings.h>
#import <NetworkExtension/NEIPv4Settings.h>
#import <NetworkExtension/NEDNSSettings.h>
#import <NetworkExtension/NEPacketTunnelFlow.h>
#import <UserNotifications/UserNotifications.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <stdatomic.h>
#import "AppInfo.h"
#import "AppProfiler.h"
#import "PacketTunnelProvider.h"
#import "PsiphonConfigReader.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "Logging.h"
#import "PacketTunnelUtils.h"
#import "NSError+Convenience.h"
#import "Asserts.h"
#import "NSDate+PSIDateExtension.h"
#import "DispatchUtils.h"
#import "DebugUtils.h"
#import "FileUtils.h"
#import "AuthorizationStore.h"
#import "FeedbackUtils.h"
#import "VPNStrings.h"
#import "NSUserDefaults+KeyedDataStore.h"
#import "ExtensionDataStore.h"
#import "HostAppProtocol.h"
#import "NSString+Additions.h"
#import "LocalNotificationService.h"

NSErrorDomain _Nonnull const PsiphonTunnelErrorDomain = @"PsiphonTunnelErrorDomain";

// UserNotifications identifiers
NSString *_Nonnull const UserNotificationDisallowedTrafficAlertIdentifier =
@"DisallowedTrafficAlertId";

// UserDefaults key for the ID of the last authorization obtained from the verifier server.
NSString *_Nonnull const UserDefaultsLastAuthID = @"LastAuthID";
NSString *_Nonnull const UserDefaultsLastAuthAccessType = @"LastAuthAccessType";

PsiFeedbackLogType const AuthCheckLogType = @"AuthCheckLogType";
PsiFeedbackLogType const ExtensionNotificationLogType = @"ExtensionNotification";
PsiFeedbackLogType const PsiphonTunnelDelegateLogType = @"PsiphonTunnelDelegate";
PsiFeedbackLogType const PacketTunnelProviderLogType = @"PacketTunnelProvider";
PsiFeedbackLogType const ExitReasonLogType = @"ExitReason";

/** PacketTunnelProvider state */
typedef NS_ENUM(NSInteger, TunnelProviderState) {
    /** @const TunnelProviderStateInit PacketTunnelProvider instance is initialized. */
    TunnelProviderStateInit,
    /** @const TunnelProviderStateStarted PacketTunnelProvider has started PsiphonTunnel. */
    TunnelProviderStateStarted,
    /** @const TunnelProviderStateZombie PacketTunnelProvider has entered zombie state, all packets will be eaten. */
    TunnelProviderStateZombie,
    /** @const TunnelProviderStateKillMessageSent PacketTunnelProvider has displayed a message to the user that it will exit soon or when the message has been dismissed by the user. */
    TunnelProviderStateKillMessageSent
};

@interface PacketTunnelProvider () <NotifierObserver>

/**
 * PacketTunnelProvider state.
 */
@property (atomic) TunnelProviderState tunnelProviderState;

// waitForContainerStartVPNCommand signals that the extension should wait for the container
// before starting the VPN.
@property (atomic) BOOL waitForContainerStartVPNCommand;

@property (nonatomic, nonnull) PsiphonTunnel *psiphonTunnel;

// Notifier message state management.
@property (atomic) BOOL postedNetworkConnectivityFailed;

// Represents if the first tunnel should use subscription check sponsor ID.
@property (atomic) BOOL startWithSubscriptionCheckSponsorID;

@property (nonatomic) HostAppProtocol *hostAppProtocol;

@end

@implementation PacketTunnelProvider {

    // Serial queue of work to be done following callbacks from PsiphonTunnel.
    dispatch_queue_t workQueue;

    AppProfiler *_Nullable appProfiler;
    
    // sessionConfigValues should only be accessed through the `workQueue`.
    AuthorizationStore *_Nonnull authorizationStore;
    
    // localDataStore should only be accessed through the `workQueue`.
    ExtensionDataStore *_Nonnull localDataStore;
    
    PsiphonConfigSponsorIds *_Nullable psiphonConfigSponsorIds;
}

- (id)init {
    self = [super init];
    if (self) {
        [AppProfiler logMemoryReportWithTag:@"PacketTunnelProviderInit"];

        workQueue = dispatch_queue_create("ca.psiphon.PsiphonVPN.workQueue", DISPATCH_QUEUE_SERIAL);

        _psiphonTunnel = [PsiphonTunnel newPsiphonTunnel:(id <TunneledAppDelegate>) self];

        _tunnelProviderState = TunnelProviderStateInit;
        _waitForContainerStartVPNCommand = FALSE;

        _postedNetworkConnectivityFailed = FALSE;
        _startWithSubscriptionCheckSponsorID = FALSE;
        
        authorizationStore = [[AuthorizationStore alloc] init];
        
        psiphonConfigSponsorIds = nil;
        
        localDataStore = [ExtensionDataStore standard];
        
        _hostAppProtocol = [[HostAppProtocol alloc] init];
    }
    return self;
}

// For debug builds starts or stops app profiler based on `sharedDB` state.
// For prod builds only starts app profiler.
- (void)updateAppProfiling {
#if DEBUG
    BOOL start = self.sharedDB.getDebugMemoryProfiler;
#else
    BOOL start = TRUE;
#endif

    if (!appProfiler && start) {
        appProfiler = [[AppProfiler alloc] init];
        [appProfiler startProfilingWithStartInterval:1
                                          forNumLogs:10
                         andThenExponentialBackoffTo:60*30
                            withNumLogsAtEachBackOff:1];

    } else if (!start) {
        [appProfiler stopProfiling];
    }
}

/// If no authorization is currently in use, gets a new persisted authorization value and
/// reconnects the Psiphon tunnel if any are found.
- (void)checkAuthorizationAndReconnectIfNeeded {
    dispatch_async(self->workQueue, ^{
        
        // Guards that Psiphon tunnel is connected.
        if (PsiphonConnectionStateConnected != self.psiphonTunnel.getConnectionState) {
            return;
        }
        
        NSSet<NSString *> *_Nullable newAuthorizations = [self->authorizationStore
                                                          getNewAuthorizations];
        
        // Reconnects the Psiphon tunnel if there are new authorization values.
        if (newAuthorizations != nil) {
            
            // Sets VPN reasserting to TRUE before the tunnel goes down for reconnection.
            self.reasserting = TRUE;
            
            [AppProfiler logMemoryReportWithTag:@"reconnectWithConfig"];
            
            NSString *sponsorId = [self->authorizationStore
                                   getSponsorId:self->psiphonConfigSponsorIds
                                   updatedSharedDB:self.sharedDB];
            
            [self.psiphonTunnel reconnectWithConfig:sponsorId :[newAuthorizations allObjects]];
            
        }
        
    });
}

// This method is not thread-safe.
- (NSError *_Nullable)startPsiphonTunnel {
    
    BOOL success = [self.psiphonTunnel start:FALSE];

    if (!success) {
        [PsiFeedbackLogger error:@"tunnel start failed"];
        return [NSError errorWithDomain:PsiphonTunnelErrorDomain
                                   code:PsiphonTunnelErrorInternalError];
    }

    self.tunnelProviderState = TunnelProviderStateStarted;
    return nil;
}

// VPN should only start if it is started from the container app directly,
// OR if the user possibly has a valid subscription
// OR if the extension is started after boot but before being unlocked.
- (void)startTunnelWithOptions:(NSDictionary<NSString *, NSObject *> *_Nullable)options
                  errorHandler:(void (^)(NSError *error))errorHandler {

    __weak PacketTunnelProvider *weakSelf = self;

    // In prod starts app profiling.
    [self updateAppProfiling];

    [[Notifier sharedInstance] registerObserver:self callbackQueue:workQueue];

    [PsiFeedbackLogger infoWithType:PacketTunnelProviderLogType
                               json:@{
                                   @"Event":@"Start",
                                   @"StartOptions": [FeedbackUtils
                                                     startTunnelOptionsFeedbackLog:options],
                                   @"StartMethod": [self extensionStartMethodTextDescription]
                               }];
    
    if (options != nil && [((NSString*)options[EXTENSION_OPTION_SUBSCRIPTION_CHECK_SPONSOR_ID])
         isEqualToString:EXTENSION_OPTION_TRUE]) {
        self.startWithSubscriptionCheckSponsorID = TRUE;
    } else {
        self.startWithSubscriptionCheckSponsorID = FALSE;
    }
    
    BOOL hasSubscriptionAuth = [authorizationStore hasSubscriptionAuth];
    
    // Increments "VPN Session" number when the network extension is started
    // from the container or other methods.
    // Note: This implies that network extension process start after a detected carsh
    //       or from boot do not increment the "VPN Session" number.
    if (self.extensionStartMethod == ExtensionStartMethodFromContainer ||
        self.extensionStartMethod == ExtensionStartMethodOther) {
        [self.sharedDB incrementVPNSessionNumber];
    }

    if (self.extensionStartMethod == ExtensionStartMethodFromContainer ||
        self.extensionStartMethod == ExtensionStartMethodFromBoot ||
        self.extensionStartMethod == ExtensionStartMethodFromCrash ||
        hasSubscriptionAuth == TRUE) {

        [self.sharedDB setExtensionIsZombie:FALSE];

        // Sets values of waitForContainerStartVPNCommand.
        {
            if (hasSubscriptionAuth == FALSE &&
                self.extensionStartMethod == ExtensionStartMethodFromContainer) {
                self.waitForContainerStartVPNCommand = TRUE;
            }
        }

        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *_Nullable error) {

            if (error != nil) {
                [PsiFeedbackLogger error:@"setTunnelNetworkSettings failed: %@", error];
                errorHandler([NSError errorWithDomain:PsiphonTunnelErrorDomain code:PsiphonTunnelErrorBadConfiguration]);
                return;
            }

            error = [weakSelf startPsiphonTunnel];
            
            if (error) {
                errorHandler(error);
            }

        }];

    } else {

        // If the user is not a subscriber, or if their subscription has expired
        // we will call startVPN to stop "Connect On Demand" rules from kicking-in over and over if they are in effect.
        //
        // To potentially stop leaking sensitive traffic while in this state, we will route
        // the network to a dead-end by setting tunnel network settings and not starting Psiphon tunnel.
        
        [self.sharedDB setExtensionIsZombie:TRUE];

        [PsiFeedbackLogger info:@"zombie mode"];

        self.tunnelProviderState = TunnelProviderStateZombie;

        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *error) {
            [weakSelf startVPN];
            weakSelf.reasserting = TRUE;
        }];

        // Notify user that VPN is not active.
        [[LocalNotificationService shared] requestCannotStartWithoutActiveSubscription];
    }
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason {
    // Always log the stop reason.
    [PsiFeedbackLogger infoWithType:PacketTunnelProviderLogType
                               json:@{@"Event":@"Stop",
                                      @"StopReason": [PacketTunnelUtils textStopReason:reason],
                                      @"StopCode": @(reason)}];

    [self.psiphonTunnel stop];
}

#pragma mark - Query methods

- (NSNumber *)isNEZombie {
    return [NSNumber numberWithBool:self.tunnelProviderState == TunnelProviderStateZombie];
}

- (NSNumber *)isTunnelConnected {
    return [NSNumber numberWithBool:
            [self.psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected];
}

- (NSNumber *)isNetworkReachable {
    NetworkReachability status;
    if ([self.psiphonTunnel getNetworkReachabilityStatus:&status]) {
        return [NSNumber numberWithBool:status != NetworkReachabilityNotReachable];
    }
    return [NSNumber numberWithBool:FALSE];
}

#pragma mark - Notifier callback

// Expected to be called on the workQueue only.
- (void)onMessageReceived:(NotifierMessage)message {

    if ([NotifierStartVPN isEqualToString:message]) {

        LOG_DEBUG(@"container signaled VPN to start");

        if ([self.sharedDB getAppForegroundState] == TRUE || [AppInfo isiOSAppOnMac] == TRUE) {
            self.waitForContainerStartVPNCommand = FALSE;
            [self tryStartVPN];
        }

    } else if ([NotifierAppEnteredBackground isEqualToString:message]) {

        LOG_DEBUG(@"container entered background");
        
        // Only on iOS mobile devices:
        // If the container StartVPN command has not been received from the container,
        // and the container goes to the background, then alert the user to open the app.
        
        if (self.waitForContainerStartVPNCommand && [AppInfo isiOSAppOnMac] == FALSE) {
            
            // TunnelStartStopIntent integer codes are defined in VPNState.swift.
            NSInteger tunnelIntent = [self.sharedDB getContainerTunnelIntentStatus];
            
            if (tunnelIntent == TUNNEL_INTENT_START || tunnelIntent == TUNNEL_INTENT_RESTART) {
                [[LocalNotificationService shared] requestOpenContainerToConnectNotification];
            }
            
        }

    } else if ([NotifierUpdatedAuthorizations isEqualToString:message]) {

        // Restarts the tunnel only if the persisted authorizations have changed from the
        // last set of authorizations supplied to tunnel-core.
        // Checks for updated subscription authorizations.
        [self checkAuthorizationAndReconnectIfNeeded];

    }

#if DEBUG || DEV_RELEASE

    if ([NotifierDebugForceJetsam isEqualToString:message]) {
        [DebugUtils jetsamWithAllocationInterval:1 withNumberOfPages:15];

    } else if ([NotifierDebugGoProfile isEqualToString:message]) {

        NSError *e = [FileUtils createDir:self.sharedDB.goProfileDirectory];
        if (e != nil) {
            [PsiFeedbackLogger errorWithType:ExtensionNotificationLogType
                                     message:@"FailedToCreateProfileDir"
                                      object:e];
            return;
        }

        [self.psiphonTunnel writeRuntimeProfilesTo:self.sharedDB.goProfileDirectory.path
                      withCPUSampleDurationSeconds:0
                    withBlockSampleDurationSeconds:0];

        [self displayMessage:@"DEBUG: Finished writing runtime profiles."
           completionHandler:^(BOOL success) {}];

    } else if ([NotifierDebugMemoryProfiler isEqualToString:message]) {
        [self updateAppProfiling];

    } else if ([NotifierDebugCustomFunction isEqualToString:message]) {
        // Custom function.
    }

#endif

}

#pragma mark -

- (void)sleepWithCompletionHandler:(void (^)(void))completionHandler {
    [PsiFeedbackLogger infoWithType:PacketTunnelProviderLogType json:@{@"Event":@"Sleep"}];
    completionHandler();
}

- (void)wake {
    [PsiFeedbackLogger infoWithType:PacketTunnelProviderLogType json:@{@"Event":@"Wake"}];
}

- (NSArray *)getNetworkInterfacesIPv4Addresses {

    // Getting list of all interfaces' IPv4 addresses
    NSMutableArray *upIfIpAddressList = [NSMutableArray new];

    struct ifaddrs *interfaces;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *interface;
        for (interface=interfaces; interface; interface=interface->ifa_next) {

            // Only IFF_UP interfaces. Loopback is ignored.
            if (interface->ifa_flags & IFF_UP && !(interface->ifa_flags & IFF_LOOPBACK)) {

                if (interface->ifa_addr && interface->ifa_addr->sa_family==AF_INET) {
                    struct sockaddr_in *in = (struct sockaddr_in*) interface->ifa_addr;
                    NSString *interfaceAddress = [NSString stringWithUTF8String:inet_ntoa(in->sin_addr)];
                    [upIfIpAddressList addObject:interfaceAddress];
                }
            }
        }
    }

    // Free getifaddrs data
    freeifaddrs(interfaces);

    return upIfIpAddressList;
}

- (NEPacketTunnelNetworkSettings *)getTunnelSettings {

    // Select available private address range, like Android does:
    // https://github.com/Psiphon-Labs/psiphon-tunnel-core/blob/cff370d33e418772d89c3a4a117b87757e1470b2/MobileLibrary/Android/PsiphonTunnel/PsiphonTunnel.java#L718
    // NOTE that the user may still connect to a WiFi network while the VPN is enabled that could conflict with the selected
    // address range

    NSMutableDictionary *candidates = [NSMutableDictionary dictionary];
    candidates[@"192.0.2"] = @[@"192.0.2.2", @"192.0.2.1"];
    candidates[@"169"] = @[@"169.254.1.2", @"169.254.1.1"];
    candidates[@"172"] = @[@"172.16.0.2", @"172.16.0.1"];
    candidates[@"192"] = @[@"192.168.0.2", @"192.168.0.1"];
    candidates[@"10"] = @[@"10.0.0.2", @"10.0.0.1"];

    static NSString *const preferredCandidate = @"192.0.2";
    NSArray *selectedAddress = candidates[preferredCandidate];

    NSArray *networkInterfacesIPAddresses = [self getNetworkInterfacesIPv4Addresses];
    for (NSString *ipAddress in networkInterfacesIPAddresses) {
        LOG_DEBUG(@"Interface: %@", ipAddress);

        if ([ipAddress hasPrefix:@"10."]) {
            [candidates removeObjectForKey:@"10"];
        } else if ([ipAddress length] >= 6 &&
                   [[ipAddress substringToIndex:6] compare:@"172.16"] >= 0 &&
                   [[ipAddress substringToIndex:6] compare:@"172.31"] <= 0 &&
                   [ipAddress characterAtIndex:6] == '.') {
            [candidates removeObjectForKey:@"172"];
        } else if ([ipAddress hasPrefix:@"192.168"]) {
            [candidates removeObjectForKey:@"192"];
        } else if ([ipAddress hasPrefix:@"169.254"]) {
            [candidates removeObjectForKey:@"169"];
        } else if ([ipAddress hasPrefix:@"192.0.2."]) {
            [candidates removeObjectForKey:@"192.0.2"];
        }
    }

    if (candidates[preferredCandidate] == nil && [candidates count] > 0) {
        selectedAddress = candidates.allValues[0];
    }

    LOG_DEBUG(@"Selected private address: %@", selectedAddress[0]);

    NEPacketTunnelNetworkSettings *newSettings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:selectedAddress[1]];

    newSettings.IPv4Settings = [[NEIPv4Settings alloc] initWithAddresses:@[selectedAddress[0]] subnetMasks:@[@"255.255.255.0"]];

    newSettings.IPv4Settings.includedRoutes = @[[NEIPv4Route defaultRoute]];

    // TODO: split tunneling could be implemented here
    newSettings.IPv4Settings.excludedRoutes = @[];

    // TODO: call getPacketTunnelDNSResolverIPv6Address
    newSettings.DNSSettings = [[NEDNSSettings alloc] initWithServers:@[[self.psiphonTunnel getPacketTunnelDNSResolverIPv4Address]]];

    newSettings.DNSSettings.searchDomains = @[@""];

    newSettings.MTU = @([self.psiphonTunnel getPacketTunnelMTU]);

    return newSettings;
}

// Starts VPN if `self.waitForContainerStartVPNCommand` is FALSE.
- (BOOL)tryStartVPN {

    // If `waitForContainerStartVPNCommand` is TRUE, network extension
    // waits until `NotifierStartVPN` message is recieved from the host app (container).
    if (self.waitForContainerStartVPNCommand == TRUE) {
        
        // App liveness check.
        // If the host app (container) is not running, only a one-time alert
        // is presented by the network extension.
        [self.hostAppProtocol isHostAppProcessRunning:^(BOOL isProcessRunning) {
            
            if (isProcessRunning == FALSE) {
                [[LocalNotificationService shared] requestOpenContainerToConnectNotification];
            }
            
        }];
        
        return FALSE;
    }

    if ([self.psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {
        [self startVPN];
        self.reasserting = FALSE;
        return TRUE;
    }

    return FALSE;
}

@end

#pragma mark -  PacketTunnelProvider utility functions
@interface PacketTunnelProvider(Utils)
@end

@implementation PacketTunnelProvider (Utils)

// Returns true if the user has bought subscription (verified or not) or SpeedBoost.
- (BOOL)hasUserMadePurchase {
    BOOL purchased = self.startWithSubscriptionCheckSponsorID ||
    [self->authorizationStore hasActiveSubscriptionOrSpeedBoost];
    return purchased;
}

@end

#pragma mark - TunneledAppDelegate

@interface PacketTunnelProvider (AppDelegateExtension) <TunneledAppDelegate>
@end

@implementation PacketTunnelProvider (AppDelegateExtension)

- (NSString * _Nullable)getEmbeddedServerEntries {
    return nil;
}

- (NSString * _Nullable)getEmbeddedServerEntriesPath {
    return PsiphonConfigReader.embeddedServerEntriesPath;
}

- (NSDictionary * _Nullable)getPsiphonConfig {
    
    // Loads Psiphon config into memory.
    PsiphonConfigReader *psiphonConfigReader = [PsiphonConfigReader load];
    
    // Sponsor IDs present in the Psiphon config are cached.
    self->psiphonConfigSponsorIds = psiphonConfigReader.sponsorIds;

    if (psiphonConfigReader.config == nil) {
        [PsiFeedbackLogger errorWithType:PsiphonTunnelDelegateLogType
                                  format:@"Failed to get config"];
        [[LocalNotificationService shared] requestCorruptSettingsFileNotification];
        [self exitGracefully];
    }

    // iOS 15
    NSOperatingSystemVersion ios15 = {.majorVersion = 15, .minorVersion = 0, .patchVersion = 0};
    
    NSNumber *fd;
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios15]) {
        // iOS >= 15 or macOS >= 12
        fd = [TunnelFileDescriptor getTunnelFileDescriptor];
    } else {
        // Legacy. This method does not work on iOS >= 15, macOS >= 12.
        fd = (NSNumber*)[[self packetFlow] valueForKeyPath:@"socket.fileDescriptor"];
    }
    
    if (fd == nil) {
        [PsiFeedbackLogger errorWithType:PsiphonTunnelDelegateLogType
                                  format:@"Failed to locate tunnel file descriptor"];
        [self exitGracefully];
    }

    NSDictionary *tunnelUserConfigs = [self.sharedDB getTunnelCoreUserConfigs];
    
#if DEBUG || DEV_RELEASE
    NSString *tunnelUserConfigsDescription = [[tunnelUserConfigs description]
                                              stringByReplacingNewLineAndWhiteSpaces];
    [PsiFeedbackLogger infoWithType:PsiphonTunnelDelegateLogType
                             format:@"TunnelCore user configs: %@", tunnelUserConfigsDescription];
#endif

    // Get a mutable copy of the Psiphon configs.
    NSMutableDictionary *mutableConfigCopy = [psiphonConfigReader.config mutableCopy];
    
    // In case of duplicate keys, values from tunnelUserConfigs
    // will replace mutableConfigCopy.
    [mutableConfigCopy addEntriesFromDictionary:tunnelUserConfigs];
    
    mutableConfigCopy[@"PacketTunnelTunFileDescriptor"] = fd;

    mutableConfigCopy[@"ClientVersion"] = [AppInfo appVersion];

    // Configure data root directory.
    // PsiphonTunnel will store all of its files under this directory.

    NSError *err;

    NSURL *dataRootDirectory = [PsiphonDataSharedDB dataRootDirectory];
    if (dataRootDirectory == nil) {
        [PsiFeedbackLogger errorWithType:PsiphonTunnelDelegateLogType
                                  format:@"Failed to get data root directory"];
        [[LocalNotificationService shared] requestCorruptSettingsFileNotification];
        [self exitGracefully];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtURL:dataRootDirectory withIntermediateDirectories:YES attributes:nil error:&err];
    if (err != nil) {
        [PsiFeedbackLogger errorWithType:PsiphonTunnelDelegateLogType
                                 message:@"Failed to create data root directory"
                                  object:err];
        [[LocalNotificationService shared] requestCorruptSettingsFileNotification];
        [self exitGracefully];
    }

    mutableConfigCopy[@"DataRootDirectory"] = dataRootDirectory.path;

    // Ensure homepage and notice files are migrated
    NSString *oldRotatingLogNoticesPath = [self.sharedDB oldRotatingLogNoticesPath];
    if (oldRotatingLogNoticesPath) {
        mutableConfigCopy[@"MigrateRotatingNoticesFilename"] = oldRotatingLogNoticesPath;
    } else {
        [PsiFeedbackLogger infoWithType:PsiphonTunnelDelegateLogType
                                format:@"Failed to get old rotating notices log path"];
    }

    NSString *oldHomepageNoticesPath = [self.sharedDB oldHomepageNoticesPath];
    if (oldHomepageNoticesPath) {
        mutableConfigCopy[@"MigrateHomepageNoticesFilename"] = oldHomepageNoticesPath;
    } else {
        [PsiFeedbackLogger infoWithType:PsiphonTunnelDelegateLogType
                                format:@"Failed to get old homepage notices path"];
    }

    // Use default rotation rules for homepage and notice files.
    // Note: homepage and notice files are only used if this field is set.
    NSMutableDictionary *noticeFiles = [[NSMutableDictionary alloc] init];
    [noticeFiles setObject:@0 forKey:@"RotatingFileSize"];
    [noticeFiles setObject:@0 forKey:@"RotatingSyncFrequency"];

    mutableConfigCopy[@"UseNoticeFiles"] = noticeFiles;
    
    // Selects an authorization for use by Psiphon tunnel.
    //
    // NOTE: Clients should not submit multiple authorizations of the same type.
    //       Extra authorizations of the same type will not be included
    //       in the onActiveAuthorizationIDs callback.
    
    NSArray<NSString *> *authorizations = [[self->authorizationStore getNewAuthorizations] allObjects];
    if (authorizations != nil) {
        mutableConfigCopy[@"Authorizations"] = authorizations;
    }
    
    if (self.startWithSubscriptionCheckSponsorID) {
        mutableConfigCopy[@"SponsorId"] = self->psiphonConfigSponsorIds.checkSubscriptionSponsorId;
    } else {
        // Determines SponsorId given the selected authorization.
        mutableConfigCopy[@"SponsorId"] = [self->authorizationStore
                                           getSponsorId:self->psiphonConfigSponsorIds
                                           updatedSharedDB:self.sharedDB];
    }

    // Specific config changes for iOS VPN app on Mac.
    if ([AppInfo isiOSAppOnMac] == TRUE) {
        [mutableConfigCopy removeObjectForKey:@"LimitIntensiveConnectionWorkers"];
        [mutableConfigCopy removeObjectForKey:@"LimitMeekBufferSizes"];
        [mutableConfigCopy removeObjectForKey:@"StaggerConnectionWorkersMilliseconds"];
    }

    return mutableConfigCopy;
}

- (void)onConnectionStateChangedFrom:(PsiphonConnectionState)oldState to:(PsiphonConnectionState)newState {
    
#if DEBUG || DEV_RELEASE
    
    PacketTunnelProvider *__weak weakSelf = self;

    dispatch_async(self->workQueue, ^{
        NSString *stateStr = [PacketTunnelUtils textPsiphonConnectionState:newState];
        [weakSelf.sharedDB setDebugPsiphonConnectionState:stateStr];
        [[Notifier sharedInstance] post:NotifierDebugPsiphonTunnelState];
    });
    
#endif

}

- (void)onConnecting {
    self.reasserting = TRUE;
}

- (void)onActiveAuthorizationIDs:(NSArray * _Nonnull)authorizationIds {
    PacketTunnelProvider *__weak weakSelf = self;
    
    dispatch_async(self->workQueue, ^{
        PacketTunnelProvider *__strong strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        BOOL subscriptionRejected = [strongSelf->authorizationStore
                                     setActiveAuthorizations:authorizationIds];
        
        // Displays an alert to the user for the expired subscription,
        // only if the container is in background.
        if (subscriptionRejected && [strongSelf.sharedDB getAppForegroundState] == FALSE) {
            [[LocalNotificationService shared] requestSubscriptionExpiredNotification];
        }
        
    });
}

- (void)onConnected {
    PacketTunnelProvider *__weak weakSelf = self;
    
    dispatch_async(self->workQueue, ^{
        PacketTunnelProvider *__strong strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        
        [AppProfiler logMemoryReportWithTag:@"onConnected"];
        [[Notifier sharedInstance] post:NotifierTunnelConnected];
        [self tryStartVPN];
        
        // Reconnect if authorizations have changed.
        [self checkAuthorizationAndReconnectIfNeeded];
    });
}

- (void)onServerTimestamp:(NSString * _Nonnull)timestamp {
    dispatch_async(self->workQueue, ^{
        [self.sharedDB updateServerTimestamp:timestamp];
    });
}

- (void)onServerAlert:(NSString * _Nonnull)reason :(NSString * _Nonnull)subject :(NSArray * _Nonnull)actionURLs {
    dispatch_async(self->workQueue, ^{
        if ([reason isEqualToString:@"disallowed-traffic"] && [subject isEqualToString:@""]) {
            
            // Alert can be displayed if the user doesn't have a subscription (verified or not),
            // or an active Speed Boost.
            BOOL canDisplayAlert = ![self hasUserMadePurchase];
            
            [PsiFeedbackLogger infoWithType:PacketTunnelProviderLogType
                                     format:@"disallowed-traffic server alert: notify user: %@",
             NSStringFromBOOL(canDisplayAlert)];
            
            // Determines if the user is subscribed or speed-boosted.
            if (canDisplayAlert == TRUE) {
                // Notifies the extension of the server alert.
                [self.sharedDB incrementDisallowedTrafficAlertWriteSequenceNum];
                [[Notifier sharedInstance] post:NotifierDisallowedTrafficAlert];
                
                // Displays notification to the user.
                [[LocalNotificationService shared] requestDisallowedTrafficNotification];
            }
        }
    });
}

- (void)onApplicationParameter:(NSString * _Nonnull)key :(id)value {
    if ([key isEqualToString:@"ShowPurchaseRequiredPrompt"]) {
        if ([value isKindOfClass:[NSNumber class]]) {
            
            NSDate *timestamp = [NSDate date];
            
            BOOL purchaseRequired = [(NSNumber *)value boolValue];
            if (purchaseRequired && ![self hasUserMadePurchase]) {
                
                // Record timestamp of event and increment seq number.
                [self.sharedDB setPurchaseRequiredPromptEventTimestamp:timestamp];
                [self.sharedDB incrementPurchaseRequiredPromptWriteSequenceNum];
                [[Notifier sharedInstance] post:NotifierPurchaseRequired];
                
                // Display location notification.
                // TODO: This notification is not debounced for the current VPN session.
                [[LocalNotificationService shared] requestPurchaseRequiredPrompt];
            }
        } else {
            [PsiFeedbackLogger error:@"Expected bool for ApplicationParameter key 'ShowPurchaseRequiredPrompt'"];
        }
    }
}

- (void)onAvailableEgressRegions:(NSArray *)regions {
    [self.sharedDB setEmittedEgressRegions:regions];
    [[Notifier sharedInstance] post:NotifierAvailableEgressRegions];
    
    NSString *selectedRegion = [self.sharedDB getEgressRegion];
    if (selectedRegion &&
        ![selectedRegion isEqualToString:kPsiphonRegionBestPerformance] &&
        ![regions containsObject:selectedRegion]) {

        [self.sharedDB setEgressRegion:kPsiphonRegionBestPerformance];

        dispatch_async(self->workQueue, ^{
            [[LocalNotificationService shared] requestSelectedRegionUnavailableNotification];
            
            // Starting the tunnel with "Best Performance" region.
            [self startPsiphonTunnel];
        });
    }
}

- (void)onInternetReachabilityChanged:(NetworkReachability)s {
    if (s == NetworkReachabilityNotReachable) {
        self.postedNetworkConnectivityFailed = TRUE;
        [[Notifier sharedInstance] post:NotifierNetworkConnectivityFailed];

    } else if (self.postedNetworkConnectivityFailed) {
        self.postedNetworkConnectivityFailed = FALSE;
        [[Notifier sharedInstance] post:NotifierNetworkConnectivityResolved];
    }
    LOG_DEBUG(@"onInternetReachabilityChanged: %ld", (long)s);
}

- (void)onDiagnosticMessage:(NSString *_Nonnull)message withTimestamp:(NSString *_Nonnull)timestamp {
    [PsiFeedbackLogger logNoticeWithType:@"tunnel-core" message:message timestamp:timestamp];
}

- (void)onUpstreamProxyError:(NSString *_Nonnull)message {
    // onUpstreamProxyError may be called concurrently.
    [[LocalNotificationService shared] requestUpstreamProxyErrorNotification:message];
}

- (void)onClientRegion:(NSString *)region {
    [self.sharedDB insertNewClientRegion:region];
}

@end
