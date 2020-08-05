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
#import "PsiphonConfigUserDefaults.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "Logging.h"
#import "RegionAdapter.h"
#import "PacketTunnelUtils.h"
#import "NSError+Convenience.h"
#import "RACSignal+Operations.h"
#import "RACDisposable.h"
#import "RACTuple.h"
#import "RACSignal+Operations2.h"
#import "RACScheduler.h"
#import "Asserts.h"
#import "NSDate+PSIDateExtension.h"
#import "DispatchUtils.h"
#import "RACUnit.h"
#import "DebugUtils.h"
#import "FileUtils.h"
#import "Strings.h"
#import "SubscriptionAuthCheck.h"
#import "SessionConfigValues.h"
#import "FeedbackUtils.h"
#import "VPNStrings.h"

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

@property (atomic) BOOL startWithSubscriptionCheckSponsorID;

@end

@implementation PacketTunnelProvider {

    _Atomic BOOL showUpstreamProxyErrorMessage;

    // Serial queue of work to be done following callbacks from PsiphonTunnel.
    dispatch_queue_t workQueue;

    AppProfiler *_Nullable appProfiler;
    
    // sessionConfigValues is not thread-safe.
    SessionConfigValues *_Nonnull sessionConfigValues;
}

- (id)init {
    self = [super init];
    if (self) {
        [AppProfiler logMemoryReportWithTag:@"PacketTunnelProviderInit"];

        atomic_init(&self->showUpstreamProxyErrorMessage, TRUE);

        workQueue = dispatch_queue_create("ca.psiphon.PsiphonVPN.workQueue", DISPATCH_QUEUE_SERIAL);

        _psiphonTunnel = [PsiphonTunnel newPsiphonTunnel:(id <TunneledAppDelegate>) self];

        _tunnelProviderState = TunnelProviderStateInit;
        _waitForContainerStartVPNCommand = FALSE;

        _postedNetworkConnectivityFailed = FALSE;
        _startWithSubscriptionCheckSponsorID = FALSE;
        
        sessionConfigValues = [[SessionConfigValues alloc] initWithSharedDB:self.sharedDB];
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

- (void)checkAuthorizationsChangeAndReconnectIfNeeded {
    dispatch_async(self->workQueue, ^{
        
        // Guards that Psiphon tunnel is connected.
        if (PsiphonConnectionStateConnected != self.psiphonTunnel.getConnectionState) {
            return;
        }
        
        // If authorizations stored by the container have been updated,
        // reconnects with the updated values.
        
        AuthorizationUpdateResult result = [self->sessionConfigValues updateStoredAuthorizations];
        switch (result) {
            case AuthorizationUpdateResultNoChange:
                return;
                
            case AuthorizationUpdateResultNoNewAuths:
                return;
                
            case AuthorizationUpdateResultNewAuthsAvailable: {
                NSString *sponsorID = nil;
                NSArray<NSString *> *_Nonnull auths = [self->sessionConfigValues
                                                       getEncodedAuthsWithSponsorID:&sponsorID];
                
                [AppProfiler logMemoryReportWithTag:@"reconnectWithConfig"];
                [self.psiphonTunnel reconnectWithConfig:sponsorID :auths];
                break;
            }
        }
    });
}


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

    [[Notifier sharedInstance] registerObserver:self callbackQueue:dispatch_get_main_queue()];

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

    if (self.extensionStartMethod == ExtensionStartMethodFromContainer ||
        self.extensionStartMethod == ExtensionStartMethodFromCrash ||
        [sessionConfigValues hasSubscriptionAuth] == TRUE) {

        [self.sharedDB setExtensionIsZombie:FALSE];

        if ([sessionConfigValues hasSubscriptionAuth] == FALSE &&
            self.extensionStartMethod == ExtensionStartMethodFromContainer) {
            self.waitForContainerStartVPNCommand = TRUE;
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

        [self displayRepeatingZombieAlert];
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

- (void)displayMessageAndExitGracefully:(NSString *)message {

    // If failed to display, retry in 60 seconds.
    const int64_t retryInterval = 60;

    __weak __block void (^weakDisplayAndKill)(NSString *message);
    void (^displayAndKill)(NSString *message);

    weakDisplayAndKill = displayAndKill = ^(NSString *message) {

        [self displayMessage:message completionHandler:^(BOOL success) {

            // If failed, retry again in `retryInterval` seconds.
            if (!success) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, retryInterval * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    weakDisplayAndKill(message);
                });
            }

            // Exit only after the user has dismissed the message.
            [self exitGracefully];
        }];
    };

    if (self.tunnelProviderState == TunnelProviderStateKillMessageSent) {
        return;
    }

    self.tunnelProviderState = TunnelProviderStateKillMessageSent;

    displayAndKill(message);
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
    NetworkStatus status;
    if ([self.psiphonTunnel getNetworkReachabilityStatus:&status]) {
        return [NSNumber numberWithBool:status != NotReachable];
    }
    return [NSNumber numberWithBool:FALSE];
}

#pragma mark - Notifier callback

- (void)onMessageReceived:(NotifierMessage)message {

    if ([NotifierStartVPN isEqualToString:message]) {

        LOG_DEBUG(@"container signaled VPN to start");

        if ([self.sharedDB getAppForegroundState] == TRUE) {
            self.waitForContainerStartVPNCommand = FALSE;
            [self tryStartVPN];
        }

    } else if ([NotifierAppEnteredBackground isEqualToString:message]) {

        LOG_DEBUG(@"container entered background");
        
        // TunnelStartStopIntent integer codes are defined in VPNState.swift.
        NSInteger tunnelIntent = [self.sharedDB getContainerTunnelIntentStatus];
        
        // If the container StartVPN command has not been received from the container,
        // and the container goes to the background, then alert the user to open the app.
        if (self.waitForContainerStartVPNCommand && tunnelIntent == TUNNEL_INTENT_START) {
            [self displayMessage:VPNStrings.openPsiphonAppToFinishConnecting];
        }

    } else if ([NotifierUpdatedNonSubscriptionAuths isEqualToString:message]) {

        // Restarts the tunnel only if the persisted authorizations have changed from the
        // last set of authorizations supplied to tunnel-core.
        [self checkAuthorizationsChangeAndReconnectIfNeeded];

    } else if ([NotifierUpdatedSubscriptionAuths isEqualToString:message]) {
        // Checks for updated subscription authorizations.
        // Reconnects the tunnel if there is a new authorization to be used,
        // or if the currently used authorization is no longer available.
        [self checkAuthorizationsChangeAndReconnectIfNeeded];
    }

#if DEBUG

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

        [self displayMessage:@"DEBUG: Finished writing runtime profiles."];

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

// Starts VPN and notifies the container of homepages (if any)
// when `self.waitForContainerStartVPNCommand` is FALSE.
- (BOOL)tryStartVPN {

    if (self.waitForContainerStartVPNCommand) {
        return FALSE;
    }

    if ([self.psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {
        [self startVPN];
        self.reasserting = FALSE;
        return TRUE;
    }

    return FALSE;
}

#pragma mark - Subscription and authorizations

/*!
 * Shows "subscription expired" alert to the user.
 * This alert will only be shown again after a time interval after the user *dismisses* the current alert.
 */
- (void)displayRepeatingZombieAlert {

    __weak PacketTunnelProvider *weakSelf = self;

    const int64_t intervalSec = 60; // Every minute.

    [self displayMessage: VPNStrings.cannotStartTunnelDueToSubscription
       completionHandler:^(BOOL success) {
           // If the user dismisses the message, show the alert again in intervalSec seconds.
           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, intervalSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
               [weakSelf displayRepeatingZombieAlert];
           });
       }];
}

- (void)displayCorruptSettingsFileMessage {
    [self displayMessage:VPNStrings.corruptSettingsFileAlertMessage];
}

// presentDisallowedTrafficAlertNotification presents user notification if enabled,
// or falls back to the simple NEProvider `displayMessage:completionHandler:` mechanism.
// Thread-safety: This method is thread-safe.
- (void)presentDisallowedTrafficAlertNotification {
    UNUserNotificationCenter* centre = [UNUserNotificationCenter currentNotificationCenter];
    
    [centre getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        
        if (settings.authorizationStatus != UNAuthorizationStatusAuthorized) {
            [self displayMessage: VPNStrings.disallowedTrafficAlertMessage];
        } else {
            UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
            content.title = [NSString localizedUserNotificationStringForKey:@"NOTIFICATION_TITLE_UPGRADE_PSIPHON" arguments:nil];
            content.body = [NSString localizedUserNotificationStringForKey:@"NOTIFICATION_BODY_DISALLOWED_TRAFFIC_ALERT" arguments:nil];
             
            // Delivers the notification immediately.
            UNNotificationRequest* request = [UNNotificationRequest
                                              requestWithIdentifier:UserNotificationDisallowedTrafficAlertIdentifier
                                              content:content
                                              trigger:nil];
             
            // Schedule the notification.
            [centre addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                // Falls back to presenting alert if the notification request failed.
                if (error != nil) {
                    [self displayMessage:VPNStrings.disallowedTrafficAlertMessage];
                }
            }];
        }
    }];
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

    NSDictionary *configs = [PsiphonConfigReader fromConfigFile].configs;
    if (!configs) {
        [PsiFeedbackLogger errorWithType:PsiphonTunnelDelegateLogType
                                 format:@"Failed to get config"];
        [self displayCorruptSettingsFileMessage];
        [self exitGracefully];
    }

    // Get a mutable copy of the Psiphon configs.
    NSMutableDictionary *mutableConfigCopy = [configs mutableCopy];

    // Applying mutations to config
    NSNumber *fd = (NSNumber*)[[self packetFlow] valueForKeyPath:@"socket.fileDescriptor"];

    // In case of duplicate keys, value from psiphonConfigUserDefaults
    // will replace mutableConfigCopy value.
    PsiphonConfigUserDefaults *psiphonConfigUserDefaults =
        [[PsiphonConfigUserDefaults alloc] initWithSuiteName:APP_GROUP_IDENTIFIER];
    [mutableConfigCopy addEntriesFromDictionary:[psiphonConfigUserDefaults dictionaryRepresentation]];

    mutableConfigCopy[@"PacketTunnelTunFileDescriptor"] = fd;

    mutableConfigCopy[@"ClientVersion"] = [AppInfo appVersion];

    // Configure data root directory.
    // PsiphonTunnel will store all of its files under this directory.

    NSError *err;

    NSURL *dataRootDirectory = [PsiphonDataSharedDB dataRootDirectory];
    if (dataRootDirectory == nil) {
        [PsiFeedbackLogger errorWithType:PsiphonTunnelDelegateLogType
                                 format:@"Failed to get data root directory"];
        [self displayCorruptSettingsFileMessage];
        [self exitGracefully];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtURL:dataRootDirectory withIntermediateDirectories:YES attributes:nil error:&err];
    if (err != nil) {
        [PsiFeedbackLogger errorWithType:PsiphonTunnelDelegateLogType
                                 message:@"Failed to create data root directory"
                                  object:err];
        [self displayCorruptSettingsFileMessage];
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
    
    // Provide auth tokens
    NSString *sponsorID;
    NSArray *authorizations = [self->sessionConfigValues getEncodedAuthsWithSponsorID:&sponsorID];
    if ([authorizations count] > 0) {
        mutableConfigCopy[@"Authorizations"] = [authorizations copy];
    }
    
    if (self.startWithSubscriptionCheckSponsorID) {
        mutableConfigCopy[@"SponsorId"] = self->sessionConfigValues.cachedSponsorIDs.checkSubscriptionSponsorId;
        self.startWithSubscriptionCheckSponsorID = FALSE;
    } else {
        mutableConfigCopy[@"SponsorId"] = sponsorID;
    }

    // Store current sponsor ID used for use by container.
    [self.sharedDB setCurrentSponsorId:mutableConfigCopy[@"SponsorId"]];

    return mutableConfigCopy;
}

- (void)onConnectionStateChangedFrom:(PsiphonConnectionState)oldState to:(PsiphonConnectionState)newState {
    // Do not block PsiphonTunnel callback queue.
    // Note: ReactiveObjC subjects block until all subscribers have received to the events,
    //       and also ReactiveObjC `subscribeOn` operator does not behave similar to RxJava counterpart for example.
    PacketTunnelProvider *__weak weakSelf = self;

#if DEBUG
    dispatch_async_global(^{
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
        
        ActiveAuthorizationResult result = [self->sessionConfigValues
                                            setActiveAuthorizationIDs:authorizationIds];
        
        switch (result) {
            case ActiveAuthorizationResultNone:
                return;
                
            case ActiveAuthorizationResultInactiveSubscription: {
                // Displays an alert to the user for the expired subscription.
                // This only happens if the container has not been up for 24 hours before expiry.
                if ([self.sharedDB getAppForegroundState] == FALSE) {
                    [self displayMessage: VPNStrings.subscriptionExpiredAlertMessage];
                }
                break;
            }
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
        [self checkAuthorizationsChangeAndReconnectIfNeeded];
    });
}

- (void)onServerTimestamp:(NSString * _Nonnull)timestamp {
    dispatch_async(self->workQueue, ^{
        [self.sharedDB updateServerTimestamp:timestamp];
    });
}

- (void)onServerAlert:(NSString *)reason :(NSString *)subject {
    dispatch_async(self->workQueue, ^{
        if ([reason isEqualToString:@"disallowed-traffic"] && [subject isEqualToString:@""]) {
            
            // Determines if the user is subscribed or speed-boosted.
            if ([self->sessionConfigValues hasActiveSpeedBoostOrSubscription] == FALSE) {
                
                // Notifies the extension of the server alert.
                [self.sharedDB incrementDisallowedTrafficAlertWriteSequenceNum];
                [[Notifier sharedInstance] post:NotifierDisallowedTrafficAlert];
                
                // Displays notification to the user.
                [self presentDisallowedTrafficAlertNotification];
            }
        }
    });
}

- (void)onAvailableEgressRegions:(NSArray *)regions {
    [self.sharedDB setEmittedEgressRegions:regions];

    [[Notifier sharedInstance] post:NotifierAvailableEgressRegions];

    PsiphonConfigUserDefaults *userDefaults = [PsiphonConfigUserDefaults sharedInstance];

    NSString *selectedRegion = [userDefaults egressRegion];
    if (selectedRegion &&
        ![selectedRegion isEqualToString:kPsiphonRegionBestPerformance] &&
        ![regions containsObject:selectedRegion]) {

        [[PsiphonConfigUserDefaults sharedInstance] setEgressRegion:kPsiphonRegionBestPerformance];

        dispatch_async(self->workQueue, ^{
            [self displayMessage:[Strings selectedRegionUnavailableAlertBody]];
            // Starting the tunnel with "Best Performance" region.
            [self startPsiphonTunnel];
        });
    }
}

- (void)onInternetReachabilityChanged:(Reachability* _Nonnull)reachability {
    NetworkStatus s = [reachability currentReachabilityStatus];
    if (s == NotReachable) {
        self.postedNetworkConnectivityFailed = TRUE;
        [[Notifier sharedInstance] post:NotifierNetworkConnectivityFailed];

    } else if (self.postedNetworkConnectivityFailed) {
        self.postedNetworkConnectivityFailed = FALSE;
        [[Notifier sharedInstance] post:NotifierNetworkConnectivityResolved];
    }
    NSString *strReachabilityFlags = [reachability currentReachabilityFlagsToString];
    LOG_DEBUG(@"onInternetReachabilityChanged: %@", strReachabilityFlags);
}

- (void)onDiagnosticMessage:(NSString *_Nonnull)message withTimestamp:(NSString *_Nonnull)timestamp {
    [PsiFeedbackLogger logNoticeWithType:@"tunnel-core" message:message timestamp:timestamp];
}

- (void)onUpstreamProxyError:(NSString *_Nonnull)message {

    // Display at most one error message. The many connection
    // attempts and variety of error messages from tunnel-core
    // would otherwise result in too many pop ups.

    // onUpstreamProxyError may be called concurrently.
    BOOL expected = TRUE;
    if (!atomic_compare_exchange_strong(&self->showUpstreamProxyErrorMessage, &expected, FALSE)) {
        return;
    }

    NSString *alertDisplayMessage = [NSString stringWithFormat:@"%@\n\n(%@)",
        VPNStrings.upstreamProxySettingsErrorMessage, message];

    [self displayMessage:alertDisplayMessage];
}

- (void)onClientRegion:(NSString *)region {
    [self.sharedDB insertNewClientRegion:region];
}

@end
