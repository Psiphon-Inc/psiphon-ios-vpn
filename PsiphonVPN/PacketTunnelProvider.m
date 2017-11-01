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
#import "IAPReceiptHelper.h"
#import "NSDateFormatter+RFC3339.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <stdatomic.h>

@implementation PacketTunnelProvider {

    // Pointer to startTunnelWithOptions completion handler.
    // NOTE: value is expected to be nil after completion handler has been called.
    void (^vpnStartCompletionHandler)(NSError *__nullable error);

    PsiphonTunnel *psiphonTunnel;

    PsiphonDataSharedDB *sharedDB;

    Notifier *notifier;

    // Start vpn decision. If FALSE, VPN should not be activated, even though Psiphon tunnel might be connected.
    // shouldStartVPN SHOULD NOT be altered after it is set to TRUE.
    BOOL shouldStartVPN;

    BOOL extensionIsZombie;

    // startFromBootWithReceipt is TRUE if the extension is started from boot with device is in locked state
    // AND a subscription receipt file exists.
    // This flag is used to defer subscription check, while the device is still in a locked state
    // and app receipt not readable by the extension process.
    BOOL startFromBootWithReceipt;

    _Atomic BOOL showUpstreamProxyErrorMessage;
}

- (id)init {
    self = [super init];

    if (self) {
        // Create our tunnel instance
        psiphonTunnel = [PsiphonTunnel newPsiphonTunnel:(id <TunneledAppDelegate>) self];

        //TODO: sharedDB calls are blocking, should they be done in a background thread?
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        shouldStartVPN = FALSE;
        extensionIsZombie = FALSE;

        atomic_init(&self->showUpstreamProxyErrorMessage, TRUE);
    }

    return self;
}

- (void)startTunnelWithOptions:(nullable NSDictionary<NSString *, NSObject *> *)options completionHandler:(void (^)(NSError *__nullable error))startTunnelCompletionHandler {

    // Creates boot test file if it doesn't already exist.
    // A boot test file is a file with protection type NSFileProtectionCompleteUntilFirstUserAuthentication,
    // used to test if the device is still locked since boot.
    // NOTE: it is assumed that this file is first created while the device is in an unlocked state.
    if (![self createBootTestFile]) {
        LOG_ERROR(@"Failed to create/check for boot test file");
        abort();
    }

    // List of paths to downgrade file protection to NSFileProtectionNone. The list could contain files or directories.
    NSArray<NSString *> *paths = @[
      // Note that this directory is not accessible in the container.
      [[[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] lastObject] path],
      // Shared container, containing logs and other data.
      [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path],
    ];

    // Set file protection of all files needed by the extension and Psiphon tunnel framework to NSFileProtectionNone.
    // This is required in order for "Connect On Demand" to work.
    // Extension should not start if this operation fails.
    if (![self downgradeFileProtectionToNone:paths withExceptions:@[[self getBootTestFilePath]]]) {
        LOG_ERROR(@"Aborting. Failed to set file protection.");
        abort();
    }

    // VPN should only start if it is started from the container app directly,
    // OR if the user has a valid subscription
    // OR if the extension is started after boot but before being unlocked.
    // NOTE: This is not a comprehensive subscription verification.
    BOOL hasActiveSubscription = [[IAPReceiptHelper sharedInstance] hasActiveSubscriptionForDate:[NSDate date]];
    BOOL startFromBoot = [self isStartBootTestFileLocked];
    startFromBootWithReceipt = startFromBoot && [self hasAppReceipt];
    BOOL tunnelStartedFromContainer = [((NSString *)options[EXTENSION_OPTION_START_FROM_CONTAINER]) isEqualToString:EXTENSION_TRUE];

#if DEBUG
    [self listDirectory:paths[0] resource:@"Library"];
    [self listDirectory:paths[1] resource:@"Shared container"];
    LOG_ERROR(@"startFromBootWithReceipt %d\nhasActiveSubscription: %d\ntunnelStartedFromContainer %d\n", startFromBootWithReceipt, hasActiveSubscription, tunnelStartedFromContainer);
#endif

    if (tunnelStartedFromContainer || hasActiveSubscription || startFromBootWithReceipt) {

        shouldStartVPN = hasActiveSubscription || startFromBootWithReceipt;

        if (startFromBootWithReceipt) {
            // Defer subscription check, until the device is unlocked.
            [self deferSubscriptionCheck];
        }

        if (hasActiveSubscription) {
            // Kick-off subscription timer.
            [self startSubscriptionCheckTimer];
        }

        // Listen for messages from the container
        [self listenForContainerMessages];

        __weak PsiphonTunnel *weakPsiphonTunnel = psiphonTunnel;

        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *_Nullable error) {

            if (error != nil) {
                LOG_ERROR(@"setTunnelNetworkSettings failed: %@", error);
                startTunnelCompletionHandler([[NSError alloc] initWithDomain:kPsiphonTunnelErrorDomain code:PsiphonTunnelErrorBadConfiguration userInfo:nil]);
                return;
            }

            BOOL success = [weakPsiphonTunnel start:FALSE];
            if (!success) {
                LOG_ERROR(@"psiphonTunnel.start failed");
                startTunnelCompletionHandler([[NSError alloc] initWithDomain:kPsiphonTunnelErrorDomain code:PsiphonTunnelErrorInternalError userInfo:nil]);
                return;
            }

            // Completion handler should be called after tunnel is connected.
            vpnStartCompletionHandler = startTunnelCompletionHandler;

        }];
    } else {
        // If the user is not a subscriber, or if their subscription has expired
        // we will call the startTunnelCompletionHandler(nil) with nil to
        // stop "Connect On Demand" rules from kicking-in over and over if they are in effect.
        //
        // This method has the side-effect of showing Psiphon VPN as "Connected" in the system settings,
        // however, traffic will not be routed if setTunnelNetworkSettings:: is not called.
        // To potentially stop leaking sensitive traffic while in this state, we will route
        // the network to a dead-end by not start psiphonTunnel.

        extensionIsZombie = TRUE;

        __weak PacketTunnelProvider *weakSelf = self;
        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *error) {
            startTunnelCompletionHandler(nil);
            weakSelf.reasserting = TRUE;
        }];

        [self showRepeatingExpiredSubscriptionAlert];
    }

}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void)) completionHandler {

    // Assumes stopTunnelWithReason called exactly once only after startTunnelWithOptions.completionHandler(nil)
    if (vpnStartCompletionHandler) {
        vpnStartCompletionHandler([NSError
          errorWithDomain:kPsiphonTunnelErrorDomain code:PsiphonTunnelErrorStoppedBeforeConnected userInfo:nil]);
        vpnStartCompletionHandler = nil;
    }

    [psiphonTunnel stop];

    completionHandler();
}

- (void)killExtensionForExpireSubscription {
    [self displayMessage:NSLocalizedStringWithDefaultValue(@"TUNNEL_KILLED", nil, [NSBundle mainBundle], @"Psiphon has been stopped automatically since your subscription has expired.", @"Alert message informing user that Psiphon has been stopped automatically since the subscription has expired. Do not translate 'Psiphon'.")
       completionHandler:^(BOOL success) {
           // Do nothing.
       }];
    // NOTE: If extension tries to exit with stopTunnelWithReason::,
    // the system will create a new extension process and set the VPN state to reconnecting.
    // Therefore, to stop the VPN, we will stop the Psiphon tunnel here and simply exit the process.
    [psiphonTunnel stop];
    exit(1);
}

#define EXTENSION_RESP_TRUE_DATA [EXTENSION_RESP_TRUE dataUsingEncoding:NSUTF8StringEncoding]
#define EXTENSION_RESP_FALSE_DATA [EXTENSION_RESP_FALSE dataUsingEncoding:NSUTF8StringEncoding]

// If the Network Extension is *not* running, and the container sends
// a messages with [NETunnelProviderSession sendProviderMessage:::] then
// the system creates a new extension process, and instantiates PacketTunnelProvider.
- (void)handleAppMessage:(NSData *)messageData
       completionHandler:(nullable void (^)(NSData * __nullable responseData))completionHandler {

    if (completionHandler != nil) {

        if (messageData) {

            NSData *respData = nil;
            NSString *query = [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding];

            if ([EXTENSION_QUERY_IS_PROVIDER_ZOMBIE isEqualToString:query]) {
                // If the Psiphon tunnel has been started when the extension was started
                // responds with EXTENSION_RESP_TRUE, otherwise responds with EXTENSION_RESP_FALSE
                respData = (extensionIsZombie) ? EXTENSION_RESP_TRUE_DATA : EXTENSION_RESP_FALSE_DATA;
            } else if ([EXTENSION_QUERY_IS_TUNNEL_CONNECTED isEqualToString:query]) {
                if ([psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {
                    respData = EXTENSION_RESP_TRUE_DATA;
                } else {
                    respData = EXTENSION_RESP_FALSE_DATA;
                }
            }

            if (respData) {
                completionHandler(respData);
                return;
            }
        }

        // If completionHandler is not nil, iOS expects it to always be executed.
        completionHandler(messageData);
    }
}

- (void)sleepWithCompletionHandler:(void (^)(void))completionHandler {
    completionHandler();
}

- (void)wake {
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

    // Start the device VPN only if the app is launched from the container app,
    // OR if the user has a valid subscription,
    // OR if the extension is started after boot but before being unlocked.
    // NOTE: This is not a complete subscription verification,
    //       specifically the receipt is not verified at this point.
    BOOL hasActiveSubscription = [[IAPReceiptHelper sharedInstance] hasActiveSubscriptionForDate:[NSDate date]];
    if ([sharedDB getAppForegroundState] || hasActiveSubscription || startFromBootWithReceipt) {

        //
        if (vpnStartCompletionHandler &&
          [psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {

            vpnStartCompletionHandler(nil);
            vpnStartCompletionHandler = nil;

            [notifier post:@"NE.newHomepages"];

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
        // If the VPN start message ("M.startVPN") has not been received from the container,
        // and the container goes to the background, then alert the user to open the app.
        //
        // Note: We expect the value of shouldStartVPN to not be altered after it is set to TRUE.
        if (!shouldStartVPN) {
            [self displayOpenAppMessage];
        }
    }];
}

/*!
 * Shows "subscription expired" alert to the user.
 * This alert will only be shown again after a time interval after the user *dismisses* the current alert.
 */
- (void)showRepeatingExpiredSubscriptionAlert {

    int64_t intervalInSec = 60; // Every minute.

    [self displayMessage:
        NSLocalizedStringWithDefaultValue(@"CANNOT_START_TUNNEL_DUE_TO_SUBSCRIPTION", nil, [NSBundle mainBundle], @"Your Psiphon subscription has expired.\nSince you're not a subscriber or your subscription has expired, Psiphon can only be started from the Psiphon app.\n\nPlease open the Psiphon app.", @"Alert message informing user that their subscription has expired or that they're not a subscriber, therefore Psiphon can only be started from the Psiphon app. DO NOT translate 'Psiphon'.")
       completionHandler:^(BOOL success) {
           // If the user dismisses the message, show the alert again in intervalInSec seconds.
           if (success) {
               dispatch_after(dispatch_time(DISPATCH_TIME_NOW, intervalInSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                   [self showRepeatingExpiredSubscriptionAlert];
               });
           }
       }];
}

// If the app receipt cannot be accessed while the device is locked,
// defer subscription check to a later time.
- (void)deferSubscriptionCheck {
    // Checks every subscriptionDeferralIntervalInSec seconds if the subscription receipt is valid.
    // If cannot read subscription, defer again.
    // If can read subscription, and check fails, stop the tunnel.
    // If the subscription check passes: call startSubscriptionCheckTimer.

#if DEBUG
    int64_t subscriptionDeferralIntervalInSec = 5; // 5 seconds.
#else
    int64_t subscriptionDeferralIntervalInSec = 5 * 60; // 5 minutes.
#endif

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
      subscriptionDeferralIntervalInSec * NSEC_PER_SEC),
      dispatch_get_main_queue(), ^{

          if ([self isStartBootTestFileLocked]) {
              // Device is still not unlocked since boot.
              // Defer subscription check again.
              [self deferSubscriptionCheck];
          } else {
              if ([[IAPReceiptHelper sharedInstance] hasActiveSubscriptionForDate:[NSDate date]]) {
                  [self startSubscriptionCheckTimer];
              } else {
                  [self killExtensionForExpireSubscription];
              }
          }

    });
}

- (void)startSubscriptionCheckTimer {
    __weak PacketTunnelProvider *weakSelf = self;

#if DEBUG
    int64_t subscriptionCheckIntervalInSec = 5; // 5 seconds.
    int64_t gracePeriodInSec = 5; // 5 seconds.
#else
    int64_t subscriptionCheckIntervalInSec = 24 * 60 * 60;  // 24 hours.
    int64_t gracePeriodInSec = 1 * 60 * 60;  // 1 hour.
#endif

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, subscriptionCheckIntervalInSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // If user's subscription has expired, then give them an hour of extra grace period
        // before killing the tunnel.
        if ([[IAPReceiptHelper sharedInstance] hasActiveSubscriptionForDate:[NSDate date]]) {
            // User has an active subscription. Check later.
            [weakSelf startSubscriptionCheckTimer];
        } else {
            // User doesn't have an active subscription. Notify them, after making sure they've checked
            // the notification we will start an hour of extra grace period.
            [self displayMessage:NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_EXPIRED_WILL_KILL_TUNNEL", nil, [NSBundle mainBundle], @"Your Psiphon subscription has expired. Psiphon will stop automatically in an hour if subscription is not renewed. Open the Psiphon app to review your subscription to continue using premium features.", @"Alert message informing user that their subscription has expired, and that Psiphon will stop in an hour if subscription is not renewed. Do not translate 'Psiphon'.")
               completionHandler:^(BOOL success) {
                   // Wait for the user to acknowledge the message before starting the extra grace period.
                   if (success) {
                       dispatch_after(dispatch_time(DISPATCH_TIME_NOW, gracePeriodInSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                           // Grace period has finished. Checks if the subscription has been renewed, otherwise kill the VPN.
                           if ([[IAPReceiptHelper sharedInstance] hasActiveSubscriptionForDate:[NSDate date]]) {
                               // Subscription has been renewed.
                               [weakSelf startSubscriptionCheckTimer];
                           } else {
                               // Subscription has not been renewed. Stop the tunnel.
                               [self killExtensionForExpireSubscription];
                           }
                       });
                   }
               }];
        }
    });
}

// hasAppReceipt returns TRUE if an app receipt file exists, FALSE otherwise.
// This method doesn't check the content of the receipt.
- (BOOL)hasAppReceipt {
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:[[[NSBundle mainBundle] appStoreReceiptURL] path]];
}

- (BOOL)isStartBootTestFileLocked {
    FILE *fp = fopen([[self getBootTestFilePath] UTF8String], "r");
    if (fp == NULL && errno == EPERM) {
        return TRUE;
    }
    if (fp != NULL) fclose(fp);
    return FALSE;
}

- (BOOL)createBootTestFile {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Need to check for existence of file, even though the extension may not have permission to open it.
    if (![fm fileExistsAtPath:[self getBootTestFilePath]]) {
        return [fm createFileAtPath:[self getBootTestFilePath]
                    contents:[@"boot_test_file" dataUsingEncoding:NSUTF8StringEncoding]
                  attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}];
    }

    return TRUE;
}

/*!
 * downgradeFileProtectionToNone sets the file protection type of paths to NSFileProtectionNone
 * so that they can be read from or written to at any time.
 * Attributes of exceptions remain untouched.
 * This is required for VPN "Connect On Demand" to work.
 * NOTE: All files containing sensitive information about the user should have file protection level
 *       NSFileProtectionCompleteUntilFirstUserAuthentication at the minimum. This is solely required for protecting
 *       user's data.
 *
 * @param paths List of file or directory paths to downgrade to NSFileProtectionNone.
 * @param exceptions List of file or directory paths to exclude from the downgrade operation.
 * @return TRUE if operation finished successfully, FALSE otherwise.
 */
- (BOOL)downgradeFileProtectionToNone:(NSArray<NSString *> *)paths withExceptions:(NSArray<NSString *> *)exceptions {
    for (NSString *path in paths) {
        if (![self setFileProtectionNoneRecursively:path withExceptions:exceptions]) {
            return FALSE;
        }
    }
    return TRUE;
}

#pragma mark - Helper methods

- (NSString *)getBootTestFilePath {
    return [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path]
      stringByAppendingPathComponent:BOOT_TEST_FILE_NAME];
}

- (BOOL)setFileProtectionNoneRecursively:(NSString *)path withExceptions:(NSArray<NSString *> *)exceptions{

    NSError *err;
    NSFileManager *fm = [NSFileManager defaultManager];

    BOOL isDirectory;
    if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && ![exceptions containsObject:path]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&err];
        if (err) {
            LOG_ERROR(@"Failed to get file attributes for path (%@) (%@)", path, err);
            return FALSE;
        }

        if (attrs[NSFileProtectionKey] != NSFileProtectionNone) {
            [fm setAttributes:@{NSFileProtectionKey: NSFileProtectionNone} ofItemAtPath:path error:&err];
            if (err) {
                LOG_ERROR(@"Failed to set the protection level of dir(%@)", path);
                return FALSE;
            }
        }

        if (isDirectory) {
            NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:path error:&err];
            if (err) {
                LOG_ERROR(@"Failed to get contents of directory (%@) (%@)", path, err);
            }

            for (NSString * item in contents) {
                if (![self setFileProtectionNoneRecursively:[path stringByAppendingPathComponent:item] withExceptions:exceptions]) {
                    return FALSE;
                }
            }

        }

    }

    return TRUE;
}

- (void)displayOpenAppMessage {
    [self displayMessage:
        NSLocalizedStringWithDefaultValue(@"OPEN_PSIPHON_APP", nil, [NSBundle mainBundle], @"Please open Psiphon app to finish connecting.", @"Alert message informing the user they should open the app to finish connecting to the VPN. DO NOT translate 'Psiphon'.")
       completionHandler:^(BOOL success) {
           // TODO: error handling?
       }];
}

#if DEBUG
- (void)listDirectory:(NSString *)dir resource:(NSString *)resource{
    NSError *err;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *desc = [NSMutableArray array];

    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:dir error:&err];

    NSDictionary *dirattrs = [fm attributesOfItemAtPath:dir error:&err];
    LOG_ERROR(@"Dir (%@) attributes:\n\n%@", [dir lastPathComponent], dirattrs[NSFileProtectionKey]);

    if ([files count] > 0) {
        for (NSString *f in files) {
            NSString *file;
            if (![[f stringByDeletingLastPathComponent] isEqualToString:dir]) {
                file = [dir stringByAppendingPathComponent:f];
            } else {
                file = f;
            }

            BOOL isDir;
            [fm fileExistsAtPath:file isDirectory:&isDir];
            NSDictionary *attrs = [fm attributesOfItemAtPath:file error:&err];
            if (err) {
//            LOG_ERROR(@"filepath: %@, %@",file, err);
            }
            [desc addObject:[NSString stringWithFormat:@"%@ : %@ : %@", [file lastPathComponent], (isDir) ? @"dir" : @"file", attrs[NSFileProtectionKey]]];
        }

        LOG_ERROR(@"Resource (%@) Checking files at dir (%@)\n%@", resource, [dir lastPathComponent], desc);
    }
}
#endif

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
        LOG_ERROR(@"%@", [NSString stringWithFormat:@"Aborting. Failed to parse config JSON: %@", err.description]);
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

    // SponsorId override
    NSString* sponsorId = [sharedDB getSponsorId];
    if(sponsorId && [sponsorId length]) {
        mutableConfigCopy[@"SponsorId"] = sponsorId;
    }

    jsonData  = [NSJSONSerialization dataWithJSONObject:mutableConfigCopy
      options:0 error:&err];

    if (err) {
        LOG_ERROR(@"Aborting. Failed to create JSON data from config object: %@", err);
        abort();
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)onConnecting {
    LOG_DEBUG(@"onConnecting");

    self.reasserting = TRUE;
}

- (void)onConnected {
    LOG_DEBUG(@"onConnected");

    if (!vpnStartCompletionHandler) {
        self.reasserting = FALSE;
    }

    [notifier post:@"NE.tunnelConnected"];

    [self tryStartVPN];
}

- (void)onServerTimestamp:(NSString * _Nonnull)timestamp {
	[sharedDB updateServerTimestamp:timestamp];

    // Check if user has an active subscription in the device's time
    // If NO - do nothing
    // If YES - proceed with checking the subscription against server timestamp
    if([[IAPReceiptHelper sharedInstance]hasActiveSubscriptionForDate:[NSDate date]]) {
        // The following code adapted from
        // https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/DataFormatting/Articles/dfDateFormatting10_4.html
        NSDateFormatter *rfc3339DateFormatter = [NSDateFormatter createRFC3339Formatter];

        NSString *serverTimestamp = [sharedDB getServerTimestamp];
        NSDate *serverDate = [rfc3339DateFormatter dateFromString:serverTimestamp];
        if (serverDate != nil) {
            if(![[IAPReceiptHelper sharedInstance]hasActiveSubscriptionForDate:serverDate]) {
                // User is possibly cheating, terminate the app due to 'Invalid Receipt'.
                // Stop the tunnel, show alert with title and message
                // and terminate the app due to 'Invalid Receipt' when user clicks 'OK'.
                NSString *alertMessage = NSLocalizedStringWithDefaultValue(@"BAD_CLOCK_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"We've detected the time on your device is out of sync with your time zone. Please update your clock settings and restart the app", @"Alert message informing user that the device clock needs to be updated with current time");
                [self stopTunnelWithReason:NEProviderStopReasonNone completionHandler:^{
                    // Do nothing.
                }];

                [IAPReceiptHelper  terminateForInvalidReceipt];

                [self displayMessage:alertMessage completionHandler:^(BOOL success) {
                    // Do nothing.
                }];
            }
        }
    }

}

- (void)onAvailableEgressRegions:(NSArray *)regions {
    [sharedDB insertNewEgressRegions:regions];

    // Notify container
    [notifier post:@"NE.onAvailableEgressRegions"];
}

- (void)onInternetReachabilityChanged:(Reachability* _Nonnull)reachability {
    NSString *strReachabilityFlags = [reachability currentReachabilityFlagsToString];
    LOG_DEBUG(@"%@", [NSString stringWithFormat:@"onInternetReachabilityChanged: %@", strReachabilityFlags]);
}

- (NSString * _Nullable)getHomepageNoticesPath {
    return [sharedDB homepageNoticesPath];
}

- (NSString * _Nullable)getRotatingNoticesPath {
    return [sharedDB rotatingLogNoticesPath];
}

- (void)onDiagnosticMessage:(NSString *_Nonnull)message withTimestamp:(NSString *_Nonnull)timestamp {
    LOG_ERROR(@"tunnel-core: %@:%@", timestamp, message);
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
        NSLocalizedStringWithDefaultValue(@"CHECK_UPSTREAM_PROXY_SETTING", nil, [NSBundle mainBundle], @"You have configured Psiphon to use an upstream proxy.\nHowever, we seem to be unable to connect to a Psiphon server through that proxy.\nPlease fix the settings and try again.", @"Main text in the 'Upstream Proxy Error' dialog box. This is shown when the user has directly altered these settings, and those settings are (probably) erroneous. DO NOT translate 'Psiphon'."),
            message];
    [self displayMessage:alertDisplayMessage
       completionHandler:^(BOOL success) {
           // Do nothing.
       }];
}

@end
