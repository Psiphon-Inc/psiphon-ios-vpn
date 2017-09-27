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
#import "PacketTunnelProvider.h"
#import "PsiphonConfigUserDefaults.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "Logging.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import "NSDateFormatter+RFC3339.h"

static const double kDefaultLogTruncationInterval = 12 * 60 * 60; // 12 hours

@implementation PacketTunnelProvider {

    // pointer to startTunnelWithOptions completion handler.
    // NOTE: value is expected to be nil after completion handler has been called.
    void (^vpnStartCompletionHandler)(NSError *__nullable error);

    PsiphonTunnel *psiphonTunnel;

    PsiphonDataSharedDB *sharedDB;

    // Notifier
    Notifier *notifier;

    NSMutableArray<NSString *> *handshakeHomepages;

    // State variables
    BOOL shouldStartVPN;  // Start vpn decision made by the container.

    // Time formatter for log messages.
    // NOTE: NSDateFormatter is threadsafe.
    NSDateFormatter *rfc3339Formatter;

}

- (id)init {
    self = [super init];

    if (self) {
        // Create our tunnel instance
        psiphonTunnel = [PsiphonTunnel newPsiphonTunnel:(id <TunneledAppDelegate>) self];

        //TODO: sharedDB calls are blocking, should they be done in a background thread?
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        handshakeHomepages = [[NSMutableArray alloc] init];

        // Notifier
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        // state variables
        shouldStartVPN = FALSE;
        
        // RFC3339 Time formatter
        rfc3339Formatter = [NSDateFormatter createRFC3339Formatter];
    }

    return self;
}

- (void)startTunnelWithOptions:(nullable NSDictionary<NSString *, NSObject *> *)options completionHandler:(void (^)(NSError *__nullable error))startTunnelCompletionHandler {

    // TODO: This method wouldn't work with "boot to VPN"
    if (options[EXTENSION_OPTION_START_FROM_CONTAINER]) {

        // Listen for messages from the container
        [self listenForContainerMessages];

        // Truncate logs every 12 hours
        [sharedDB truncateLogsOnInterval:(NSTimeInterval) kDefaultLogTruncationInterval];

        // Reset tunnel connected state.
        [sharedDB updateTunnelConnectedState:FALSE];

        __weak PsiphonTunnel *weakPsiphonTunnel = psiphonTunnel;

        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *_Nullable error) {

            if (error != nil) {
                LOG_ERROR(@"setTunnelNetworkSettings failed: %@", error);
                startTunnelCompletionHandler([[NSError alloc] initWithDomain:PSIPHON_TUNNEL_ERROR_DOMAIN code:PSIPHON_TUNNEL_ERROR_BAD_CONFIGURATION userInfo:nil]);
                return;
            }


            BOOL success = [weakPsiphonTunnel start:FALSE];
            if (!success) {
                LOG_ERROR(@"psiphonTunnel.start failed");
                startTunnelCompletionHandler([[NSError alloc] initWithDomain:PSIPHON_TUNNEL_ERROR_DOMAIN code:PSIPHON_TUNNEL_ERROR_INTERAL_ERROR userInfo:nil]);
                return;
            }

            // Completion handler should be called after tunnel is connected.
            vpnStartCompletionHandler = startTunnelCompletionHandler;

        }];
    } else {
        // TODO: localize the following string
        [self displayMessage:
            NSLocalizedStringWithDefaultValue(@"USE_PSIPHON_APP", nil, [NSBundle mainBundle], @"To connect, use the Psiphon app", @"Alert message informing user they have to open the app")
          completionHandler:^(BOOL success) {
              // TODO: error handling?
          }];

        startTunnelCompletionHandler([NSError
          errorWithDomain:PSIPHON_TUNNEL_ERROR_DOMAIN code:PSIPHON_TUNNEL_ERROR_BAD_START userInfo:nil]);
    }

}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void)) completionHandler {

    [sharedDB updateTunnelConnectedState:FALSE];

    // Assumes stopTunnelWithReason called exactly once only after startTunnelWithOptions.completionHandler(nil)
    if (vpnStartCompletionHandler) {
        vpnStartCompletionHandler([NSError
          errorWithDomain:PSIPHON_TUNNEL_ERROR_DOMAIN code:PSIPHON_TUNNEL_ERROR_STOPPED_BEFORE_CONNECTED userInfo:nil]);
        vpnStartCompletionHandler = nil;
    }

    [psiphonTunnel stop];

    completionHandler();

    return;
}

- (void)handleAppMessage:(NSData *)messageData completionHandler:(nullable void (^)(NSData * __nullable responseData))completionHandler {

    if (completionHandler != nil) {
        completionHandler(messageData);
    }
}

- (void)sleepWithCompletionHandler:(void (^)(void))completionHandler {
    completionHandler();
}

- (void)wake {
}

- (void)logMessage:(NSString * _Nonnull)message {
    // This is a convenience method that is not part
    [self logMessage:message withTimestamp:[rfc3339Formatter stringFromDate:[NSDate date]]];
}

- (void)logMessage:(NSString * _Nonnull)message withTimestamp:(NSString * _Nonnull)timestamp{
    // Called synchronously on PsiphonTunnel's callback queue.
    // Any database or file operations should be performed
    // synchronously before returning to guarantee ordering of
    // database insertions, writes, etc.
    [self performBackgroundTaskWithReason:@"onDiagnosticMessage" usingBlock:^{
        [sharedDB insertDiagnosticMessage:message withTimestamp:timestamp];
#if DEBUG
        // Notify container that there is new data in shared sqlite database.
        // This is only needed in debug mode where the log view is enabled
        // in the container. LogViewController needs to know when new logs
        // have entered the shared database so it can update its view to
        // display the latest diagnostic entries.
        [notifier post:@"NE.onDiagnosticMessage"];
#endif
    }];
}


/*
 * Execute block as a background task. The background task will end after your block argument returns. The reason string is used for debugging.
 *
 * This method will not return until the background task completes successfully or expires.
 * This method should be used as a wrapper for any code that can result in a lock being obtained on a file in the shared app group container.
 * This method must be used if the code could hold this manner of lock while the extension is being suspended.
 * If the extension holds a lock during suspension it will be terminated by the OS with exception code 0xdead10cc.
 */
- (void)performBackgroundTaskWithReason:(NSString * _Nonnull)reason usingBlock:(void (^)(void))block {
    // Follows template provided by "Requesting Background Assertions for Asynchronous Tasks" in:
    // https://developer.apple.com/library/content/documentation/General/Conceptual/WatchKitProgrammingGuide/iOSSupport.html
    dispatch_semaphore_t expiringActivityCompleted = dispatch_semaphore_create(0);
    dispatch_semaphore_t blockExecutedOrActivityExpired = dispatch_semaphore_create(0);
    [[NSProcessInfo processInfo] performExpiringActivityWithReason:reason usingBlock:^(BOOL expired) {
        // This block is executed on an anonymous background queue.
        // Note: this block can be called multiple times. If you are given
        // a background task assertion, the block will be called with
        // expiring == false. Then, if the app suddenly needs to terminate, the system can revoke
        // the assertion by calling this block a second time with expiring == true.
        if (expired) {
            // Your app has not been given a background task assertion,
            // or the current background task assertion has been revoked.
            
            // You have a brief bit of time to perform any clean-up activities.
            
            // Clean up any running tasks.
            // Cancel any long synchronous tasks (if possible).
            // Unblock the thread (if blocked).
            dispatch_semaphore_signal(blockExecutedOrActivityExpired);
            
            // Allow performBackgroundTaskWithReason to return.
            dispatch_semaphore_signal(expiringActivityCompleted);
        } else {
            // Your app has been given a background task assertion.
            
            // The background task assertion lasts until this method returns, or until
            // the assertion is revoked.
            
            // perform long synchronous tasks here
            // or kick off asynchronous task and block this thread.
            // Be sure to unblock the thread when the asynchronous task is complete.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                block();
                dispatch_semaphore_signal(blockExecutedOrActivityExpired);
            });
            long timedOut = dispatch_semaphore_wait(blockExecutedOrActivityExpired, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 60));
            if (timedOut == 0) {
                // Async task completed successfully or the activity was expired.
                LOG_DEBUG(@"onDiagnosticMessage: semaphore wait returned successfully");
            } else {
                LOG_DEBUG(@"onDiagnosticMessage: semaphore wait timed out");
            }
            
            // Allow performBackgroundTaskWithReason to return.
            dispatch_semaphore_signal(expiringActivityCompleted);
        }
    }];
    
    dispatch_semaphore_wait(expiringActivityCompleted, dispatch_time(DISPATCH_TIME_FOREVER, 0));
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
    
    if ([candidates objectForKey:preferredCandidate] == nil && [candidates count] > 0) {
        selectedAddress = [[candidates allValues] objectAtIndex:0];
    }
    
    LOG_DEBUG(@"Selected private address: %@", selectedAddress[0]);

    NEPacketTunnelNetworkSettings *newSettings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:selectedAddress[1]];
    
    newSettings.IPv4Settings = [[NEIPv4Settings alloc] initWithAddresses:@[selectedAddress[0]] subnetMasks:@[@"255.255.255.0"]];
    
    newSettings.IPv4Settings.includedRoutes = @[[NEIPv4Route defaultRoute]];
    
    // TODO: split tunneling could be implemented here
    newSettings.IPv4Settings.excludedRoutes = @[];

    // TODO: call getPacketTunnelDNSResolverIPv6Address
    newSettings.DNSSettings = [[NEDNSSettings alloc] initWithServers:@[[psiphonTunnel getPacketTunnelDNSResolverIPv4Address]]];

    newSettings.DNSSettings.searchDomains = @[@""];

    newSettings.MTU = @([psiphonTunnel getPacketTunnelMTU]);

    return newSettings;
}

/*!
 * @brief Calls startTunnelWithOptions completion handler
 * to start the tunnel, if the connection state is Connected.
 * @return TRUE if completion handler called, FALSE otherwise.
 */
- (BOOL)tryStartVPN {

    // Checks if the container has made the decision
    // for the VPN to be started.
    if (!shouldStartVPN) {
        return FALSE;
    }

    if ([sharedDB getAppForegroundState]) {

        if (vpnStartCompletionHandler &&
          [psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {

            vpnStartCompletionHandler(nil);
            vpnStartCompletionHandler = nil;

            if ([handshakeHomepages count] > 0) {
                BOOL success = [sharedDB updateHomepages:handshakeHomepages];
                if (success) {
                    [notifier post:@"NE.newHomepages"];
                    [handshakeHomepages removeAllObjects];
                }
            }

            return TRUE;
        }
    }

    return FALSE;
}

- (void)listenForContainerMessages {
    [notifier listenForNotification:@"M.startVPN" listener:^{
        // If the tunnel is connected, starts the VPN.
        // Otherwise, should establish the VPN after onConnected has been called.
        shouldStartVPN = TRUE; // This should be set before calling tryStartVPN.
        [self tryStartVPN];
    }];

    [notifier listenForNotification:@"D.applicationDidEnterBackground" listener:^{
        // If the VPN start message has not been received by the container,
        // and the container goes to the background alert user to open the app.
        // Note: We expect the value of shouldStartVPN to be set to TRUE on the
        //       first call to startVPN, and not be modified after that.
        if (!shouldStartVPN) {
            [self displayOpenAppMessage];
        }
    }];
}

#pragma mark - Helper methods

- (void)displayOpenAppMessage {
    [self displayMessage:
        NSLocalizedStringWithDefaultValue(@"OPEN_PSIPHON_APP", nil, [NSBundle mainBundle], @"Please open Psiphon app to finish connecting.", @"Alert message informing the user they should open the app to finish connecting to the VPN.")
       completionHandler:^(BOOL success) {
           // TODO: error handling?
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
    NSString *serverEntriesPath = [[[NSBundle mainBundle]
      resourcePath] stringByAppendingPathComponent:@"embedded_server_entries"];

    return serverEntriesPath;
}

- (NSString * _Nullable)getPsiphonConfig {

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *bundledConfigPath = [[[NSBundle mainBundle] resourcePath]
      stringByAppendingPathComponent:@"psiphon_config"];

    if (![fileManager fileExistsAtPath:bundledConfigPath]) {
        LOG_ERROR(@"Config file not found. Aborting now.");
        abort();
    }

    // Read in psiphon_config JSON
    NSData *jsonData = [fileManager contentsAtPath:bundledConfigPath];
    NSError *err = nil;
    NSDictionary *readOnly = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&err];

    if (err) {
        [self logMessage:[NSString stringWithFormat:@"Aborting. Failed to parse config JSON: %@", err.description]];
        abort();
    }

    NSMutableDictionary *mutableConfigCopy = [readOnly mutableCopy];

    // TODO: apply mutations to config here
    NSNumber *fd = (NSNumber*)[[self packetFlow] valueForKeyPath:@"socket.fileDescriptor"];

    // In case of duplicate keys, value from psiphonConfigUserDefaults
    // will replace mutableConfigCopy value.
    PsiphonConfigUserDefaults *psiphonConfigUserDefaults = [[PsiphonConfigUserDefaults alloc]
      initWithSuiteName:APP_GROUP_IDENTIFIER];
    [mutableConfigCopy addEntriesFromDictionary:[psiphonConfigUserDefaults dictionaryRepresentation]];

    mutableConfigCopy[@"PacketTunnelTunFileDescriptor"] = fd;
    
    mutableConfigCopy[@"ClientVersion"] = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

    jsonData  = [NSJSONSerialization dataWithJSONObject:mutableConfigCopy
      options:0 error:&err];

    if (err) {
        [self logMessage:[NSString stringWithFormat:@"Aborting. Failed to create JSON data from config object: %@", err.description]];
        abort();
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)onDiagnosticMessage:(NSString * _Nonnull)message withTimestamp:(NSString * _Nonnull)timestamp {
    [self logMessage:message withTimestamp:timestamp];
}

- (void)onConnecting {
    LOG_DEBUG(@"onConnecting");

    [sharedDB updateTunnelConnectedState:FALSE];

    self.reasserting = TRUE;

    // Clear list of handshakeHomepages.
    [handshakeHomepages removeAllObjects];
}

- (void)onConnected {
    LOG_DEBUG(@"onConnected");

    [sharedDB updateTunnelConnectedState:TRUE];

    if (!vpnStartCompletionHandler) {
        self.reasserting = FALSE;
    }

    [notifier post:@"NE.tunnelConnected"];

    [self tryStartVPN];
}

- (void)onExiting {
}

- (void)onHomepage:(NSString * _Nonnull)url {
    for (NSString *p in handshakeHomepages) {
        if ([url isEqualToString:p]) {
            return;
        }
    }
    [handshakeHomepages addObject:url];
}

- (void)onAvailableEgressRegions:(NSArray *)regions {
    [sharedDB insertNewEgressRegions:regions];

    // Notify container
    [notifier post:@"NE.onAvailableEgressRegions"];
}

- (void)onInternetReachabilityChanged:(Reachability* _Nonnull)reachability {
    NSString *strReachabilityFlags = [reachability currentReachabilityFlagsToString];
    [self logMessage:[NSString stringWithFormat:@"onInternetReachabilityChanged: %@", strReachabilityFlags]];
}

@end
