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
#import "SubscriptionVerifier.h"
#import "NSDateFormatter+RFC3339.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <stdatomic.h>

static NSDateFormatter *__rfc3339DateFormatter = nil;
#define kAuthorizationDictionary        @"kAuthorizationDictionary"
#define kSignedAuthorization            @"signed_authorization"
#define kAuthorizationExpires           @"kAuthorizationExpires"
#define kPendingRenewalInfo             @"pending_renewal_info"
#define kAutoRenewStatus                @"auto_renew_status"
#define kRequestDate                    @"request_date"

typedef NS_ENUM(NSInteger, PsiphonSubscriptionState) {
    PsiphonSubscriptionStateNotSubscribed,
    PsiphonSubscriptionStateMaybeSubscribed,
    PsiphonSubscriptionStateSubscribed,
};


// Notes on file protection:
// iOS has different file protection mechanisms to protect user's data. While this is important for protecting
// user's data, it is not needed (and offers no benefits) for application data.
//
// When files are created, iOS >7, defaults to protection level NSFileProtectionCompleteUntilFirstUserAuthentication.
// This affects files created and used by tunnel-core and the extension, preventing them to function if the
// process is started at boot but before the user has unlocked their device.
//
// To mitigate this situation, for the very first the extension runs, all folders and files required by the extension
// and tunnel-core are set to protection level NSFileProtectionNone. With the exception of the app subscription receipt
// file, which the process doesn't have rights to modify it's protection level.
// Therefore, checking subscription receipt is deferred indefinitely until the device is unlocked, and the process is
// able to open and read the file. (method isStartBootTestFileLocked performs the test that checks if the device
// has been unlocked or not.)

@interface PacketTunnelProvider ()

@property (nonatomic) BOOL extensionIsZombie;

@property (nonatomic)  PsiphonSubscriptionState startTunnelSubscriptionState;

// Start vpn decision. If FALSE, VPN should not be activated, even though Psiphon tunnel might be connected.
// shouldStartVPN SHOULD NOT be altered after it is set to TRUE.
@property (nonatomic) BOOL shouldStartVPN;

@end

@implementation PacketTunnelProvider {

    PsiphonTunnel *psiphonTunnel;

    PsiphonDataSharedDB *sharedDB;

    Notifier *notifier;

    NSString *_Nonnull currentSponsorId;

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

        currentSponsorId = @"";

        atomic_init(&self->showUpstreamProxyErrorMessage, TRUE);

        self.extensionIsZombie = FALSE;
    }

    return self;
}


- (void)startTunnelWithErrorHandler:(void (^_Nonnull)(NSError *_Nonnull error))errorHandler {

    // VPN should only start if it is started from the container app directly,
    // OR if the user possibly has a valid subscription
    // OR if the extension is started after boot but before being unlocked.

    NSDictionary *authorizationDictionary = [self authorizationDictionary];

    self.startTunnelSubscriptionState = PsiphonSubscriptionStateNotSubscribed;

    if([self hasActiveAuthorizationForDate:[NSDate date] inDict:authorizationDictionary]) {
        self.startTunnelSubscriptionState = PsiphonSubscriptionStateSubscribed;
    } else if ([self shouldUpdateAuthorization:authorizationDictionary]) {
        self.startTunnelSubscriptionState = PsiphonSubscriptionStateMaybeSubscribed;
    }

    if (self.NEStartMethod == NEStartMethodFromContainer || self.startTunnelSubscriptionState != PsiphonSubscriptionStateNotSubscribed) {

        // Listen for messages from the container
        [self listenForContainerMessages];

        __weak PsiphonTunnel *weakPsiphonTunnel = psiphonTunnel;

        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *_Nullable error) {

            if (error != nil) {
                LOG_ERROR(@"setTunnelNetworkSettings failed: %@", error);
                errorHandler([[NSError alloc] initWithDomain:kPsiphonTunnelErrorDomain code:PsiphonTunnelErrorBadConfiguration userInfo:nil]);
                return;
            }

            // Starts Psiphon tunnel.
            BOOL success = [weakPsiphonTunnel start:FALSE];

            if (!success) {
                LOG_ERROR(@"tunnel start failed");
                errorHandler([[NSError alloc] initWithDomain:kPsiphonTunnelErrorDomain code:PsiphonTunnelErrorInternalError userInfo:nil]);
                return;
            }

        }];

    } else {

        // If the user is not a subscriber, or if their subscription has expired
        // we will call startVPN to stop "Connect On Demand" rules from kicking-in over and over if they are in effect.
        //
        // To potentially stop leaking sensitive traffic while in this state, we will route
        // the network to a dead-end by setting tunnel network settings and not starting Psiphon tunnel.

        self.extensionIsZombie = TRUE;

        __weak PacketTunnelProvider *weakSelf = self;
        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *error) {
            [weakSelf startVPN];
            weakSelf.reasserting = TRUE;
        }];

        [self showRepeatingExpiredSubscriptionAlert];
    }
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason {
    [psiphonTunnel stop];
}

- (void)restartTunnel {
    [psiphonTunnel stop];

    if (![psiphonTunnel start:FALSE]) {
        LOG_ERROR(@"tunnel start failed");
    }
}


- (void)displayMessageAndKillExtension:(NSString*) alertMessage {
    // TODO: test : does stopTunnelWithReason get called? What is the reason?
    [psiphonTunnel stop];

    [self displayMessage:alertMessage completionHandler:^(BOOL success) {
       // Exit only after the user has clicked OK button.
       // TODO: does stopTunnelWithReason get called? maybe create our own reasons and log them.
       exit(1);
    }];
}

- (void)onVPNStarted {
    [self trySubscriptionCheck];
}

#pragma mark - Query methods

- (BOOL)isNEZombie {
    return self.extensionIsZombie;
}

- (BOOL)isTunnelConnected {
    return [psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected;
}

- (NSString *_Nonnull)sponsorId {
    return currentSponsorId;
}

#pragma mark -

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
    if (!self.shouldStartVPN) {
        return FALSE;
    }

    if ([sharedDB getAppForegroundState] || self.startTunnelSubscriptionState != PsiphonSubscriptionStateNotSubscribed) {
        if ([psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {
            if ([self startVPN]) {
                [notifier post:@"NE.newHomepages"];
                return TRUE;
            }
        }
    }

    return FALSE;
}

- (void)listenForContainerMessages {
    [notifier listenForNotification:@"M.startVPN" listener:^{
        // If the tunnel is connected, starts the VPN.
        // Otherwise, should establish the VPN after onConnected has been called.
        self.shouldStartVPN = TRUE; // This should be set before calling tryStartVPN.
        [self tryStartVPN];
    }];

    [notifier listenForNotification:@"D.applicationDidEnterBackground" listener:^{
        // If the VPN start message ("M.startVPN") has not been received from the container,
        // and the container goes to the background, then alert the user to open the app.
        //
        // Note: We expect the value of shouldStartVPN to not be altered after it is set to TRUE.
        if (!self.shouldStartVPN) {
            [self displayMessage:NSLocalizedStringWithDefaultValue(@"OPEN_PSIPHON_APP", nil, [NSBundle mainBundle], @"Please open Psiphon app to finish connecting.", @"Alert message informing the user they should open the app to finish connecting to the VPN. DO NOT translate 'Psiphon'.")];
        }
    }];
}

#pragma mark - Subscription

- (void)trySubscriptionCheck {

    if (self.VPNStarted && [psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {

        if ([self isDeviceLocked] && self.NEStartMethod == NEStartMethodFromBoot) {
            // Device is started from boot, but before the user has unlocked it first.
            // Defer subscription check, until the device is unlocked.
            // Deferral time is defined within deferSubscriptionCheck (currently every 5 minutes).
            // If the the device is never unlocked, subscription will never be checked, and the tunnel
            // will be active indefinitely until stopped.
            [self deferSubscriptionCheck];
            return;
        }

        NSDictionary *authorizationDictionary = [self authorizationDictionary];


        // TODO: does shouldUpdateSubscription.. return FALSE after the subscription dictionary has been updated.
        if ([self shouldUpdateAuthorization:authorizationDictionary]) {
            // Do remote check.
            [self updateAuthorizationDictionaryFromRemote];

        } else {
            // Check authorization.

            if ([self hasActiveAuthorizationForDate:[NSDate date] inDict:authorizationDictionary]) {

                if (self.startTunnelSubscriptionState != PsiphonSubscriptionStateSubscribed) {
                    self.startTunnelSubscriptionState = PsiphonSubscriptionStateSubscribed;
                    [self restartTunnel];
                }

                // if the user has an active subscription, checks their subscription again in an interval defined within
                // startSubscriptionCheckTimer (currently every 24 hours).
                // If the subscription expires at some point in the future, the user is given a grace period (currently 1 hour)
                // before the tunnel and the VPN are stopped completely.
                [self startSubscriptionCheckTimer];

            } else {

                if (self.NEStartMethod == NEStartMethodFromContainer) {

                    if (self.startTunnelSubscriptionState != PsiphonSubscriptionStateNotSubscribed) {
                        self.startTunnelSubscriptionState = PsiphonSubscriptionStateNotSubscribed;
                        [self restartTunnel];
                    }

                } else {
                    [self startGracePeriod];
                }
            }
        }
    }
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

          if ([self isDeviceLocked]) {
              // Device is still not unlocked since boot.
              // Defer subscription check again.
              [self deferSubscriptionCheck];
          } else {
              [self trySubscriptionCheck];
          }

    });
}

- (void)startSubscriptionCheckTimer {
    [self _startSubscriptionCheckTimer:TRUE];
}

- (void)_startSubscriptionCheckTimer:(BOOL)new {

    if (self.startTunnelSubscriptionState == PsiphonSubscriptionStateNotSubscribed) {
        return;
    }

    // TODO: implement a queue of some sort, and enable the timer to be cancellable.
    static BOOL onceToken = FALSE;
    if (onceToken && new) {
        return;
    }
    onceToken = TRUE;

    __weak PacketTunnelProvider *weakSelf = self;

    #if DEBUG
    int64_t subscriptionCheckIntervalInSec = 5; // 5 seconds.
    #else
    int64_t subscriptionCheckIntervalInSec = 24 * 60 * 60;  // 24 hours.
    #endif

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, subscriptionCheckIntervalInSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // If user's subscription has expired, then give them an hour of extra grace period
        // before killing the tunnel.
        if ([weakSelf hasActiveAuthorizationForDate:[NSDate date] inDict:[weakSelf authorizationDictionary]]) {
            // User has an active subscription. Check later.
            [weakSelf _startSubscriptionCheckTimer:FALSE];
        } else {
            [weakSelf trySubscriptionCheck];
        }
    });
}

- (void)startGracePeriod {

    #if DEBUG
    int64_t gracePeriodInSec = 5; // 5 seconds.
    #else
    int64_t gracePeriodInSec = 1 * 60 * 60;  // 1 hour.
    #endif

    __weak PacketTunnelProvider *weakSelf = self;

    // User doesn't have an active subscription. Notify them, after making sure they've checked
    // the notification we will start an hour of extra grace period.
    [self displayMessage:NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_EXPIRED_WILL_KILL_TUNNEL", nil, [NSBundle mainBundle], @"Your Psiphon subscription has expired. Psiphon will stop automatically in an hour if subscription is not renewed. Open the Psiphon app to review your subscription to continue using premium features.", @"Alert message informing user that their subscription has expired, and that Psiphon will stop in an hour if subscription is not renewed. Do not translate 'Psiphon'.")
       completionHandler:^(BOOL success) {
           // Wait for the user to acknowledge the message before starting the extra grace period.
           if (success) {
               dispatch_after(dispatch_time(DISPATCH_TIME_NOW, gracePeriodInSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                   // Grace period has finished. Checks if the subscription has been renewed, otherwise kill the VPN.
                   if ([weakSelf hasActiveAuthorizationForDate:[NSDate date] inDict:[weakSelf authorizationDictionary]]) {
                       // Subscription has been renewed.
                       [weakSelf startSubscriptionCheckTimer];
                   } else {
                       // Subscription has not been renewed. Stop the tunnel.
                       [weakSelf killExtensionForExpiredSubscription];
                   }
               });
           }
       }];
}

- (void)killExtensionForExpiredSubscription {
    NSString *alertMessage = NSLocalizedStringWithDefaultValue(@"TUNNEL_KILLED", nil, [NSBundle mainBundle], @"Psiphon has been stopped automatically since your subscription has expired.", @"Alert message informing user that Psiphon has been stopped automatically since the subscription has expired. Do not translate 'Psiphon'.");
    [self displayMessageAndKillExtension:alertMessage];
}

- (void)killExtensionForBadClock {
    NSString *alertMessage = NSLocalizedStringWithDefaultValue(@"BAD_CLOCK_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"We've detected the time on your device is out of sync with your time zone. Please update your clock settings and restart the app", @"Alert message informing user that the device clock needs to be updated with current time");
    [self displayMessageAndKillExtension:alertMessage];
}

- (void)killExtensionForInvalidReceipt {
    NSString *alertMessage = NSLocalizedStringWithDefaultValue(@"BAD_RECEIPT_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"Your subscription receipt can not be verified, please refresh it and try again.", @"Alert message informing user that subscription receipt can not be verified");
    [self displayMessageAndKillExtension:alertMessage];
}

- (void)updateAuthorizationDictionaryFromRemote {

    static BOOL _ongoing = FALSE;
    static int _retryCount = 0;
    if (_ongoing) {
        return;
    }

    _ongoing = TRUE;

    NSDictionary *authorizationDictionary = [self  authorizationDictionary];

    if (![self shouldUpdateAuthorization:authorizationDictionary]) {
        return;
    }

    __block NSMutableDictionary* remoteAuthDict = nil;
    __weak PacketTunnelProvider *weakSelf = self;

    [[[SubscriptionVerifier alloc] init] startWithCompletionHandler: ^(NSDictionary *dict, NSError *error) {

        _retryCount++;

        if (!error) {
            if (dict) {
                // add app receipt file size
                NSNumber* appReceiptFileSize = nil;
                [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:nil];

                remoteAuthDict = [[NSMutableDictionary alloc] initWithDictionary:dict];
                remoteAuthDict[kAppReceiptFileSize] = appReceiptFileSize;


                // remove old auth expires value if any.
                [remoteAuthDict removeObjectForKey:kAuthorizationExpires];
                // decode base64 encoded auth token and extract expiration date as NSDate
                NSString *base64String = remoteAuthDict[kSignedAuthorization];
                if(base64String) {
                    NSError *err;
                    NSDictionary *signedAuthDict = [NSJSONSerialization JSONObjectWithData:[[NSData alloc] initWithBase64EncodedString:base64String options:0]
                                                                         options:0 error:&err];
                    if (err) {
                        LOG_ERROR(@"Failed parsing signed authorization base64 encoded token. Error:%@", err);
                    } else {
                        NSDictionary *authorizationDict = signedAuthDict[@"Authorization"];
                        NSString* authExpiresDateString = (NSString*) authorizationDict[@"Expires"];
                        if([authExpiresDateString length]) {
                            if(!__rfc3339DateFormatter) {
                                __rfc3339DateFormatter = [NSDateFormatter createRFC3339Formatter];
                            }
                            NSDate* authExpiresDate = [__rfc3339DateFormatter dateFromString:authExpiresDateString];
                            remoteAuthDict[kAuthorizationExpires] = authExpiresDate;
                        }
                    }

                }

                // Extract request date from the response and convert to NSDate
                NSDate *requestDate = nil;
                NSString *requestDateString = (NSString*) remoteAuthDict[kRequestDate];
                [remoteAuthDict removeObjectForKey:kRequestDate];

                if([requestDateString length]) {
                    if(!__rfc3339DateFormatter) {
                        __rfc3339DateFormatter = [NSDateFormatter createRFC3339Formatter];
                    }
                    requestDate = [__rfc3339DateFormatter dateFromString:requestDateString];
                }

                [weakSelf storeAuthorizationDictionary:remoteAuthDict];

                // "Clock is off" notification  if user has an active subscription in server time
                // but in device time it appears to be expired.
                if (requestDate) {
                    if([weakSelf hasActiveAuthorizationForDate:requestDate inDict:remoteAuthDict]
                      && ![weakSelf hasActiveAuthorizationForDate:[NSDate date] inDict:remoteAuthDict]) {
                        [weakSelf killExtensionForBadClock];
                    }
                }
            }
        } else {
            LOG_ERROR(@"Subscription verifier error: %@, %ld", error.localizedDescription, (long)error.code);

            // Notify observers if invalid receipt
            if (error.code == PsiphonReceiptValidationInvalidReceiptError) {
                [weakSelf killExtensionForInvalidReceipt];

            } else if (error.code == PsiphonReceiptValidationHTTPError || error.code == PsiphonReceiptValidationNSURLSessionError) {
                // Retry again in 30 seconds.
                if (_retryCount < 5) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [weakSelf trySubscriptionCheck];
                    });
                }
            }
        }

        if (![weakSelf hasActiveAuthorizationForDate:[NSDate date] inDict:[weakSelf authorizationDictionary]] && weakSelf.startTunnelSubscriptionState != PsiphonSubscriptionStateNotSubscribed) {
            [weakSelf trySubscriptionCheck];
        }
        _ongoing = FALSE;
    }];

}

- (NSDictionary*)authorizationDictionary {
    return (NSDictionary*)[[NSUserDefaults standardUserDefaults] dictionaryForKey:kAuthorizationDictionary];
}

- (void)storeAuthorizationDictionary:(NSDictionary*)dict {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:dict forKey:kAuthorizationDictionary];
    [userDefaults synchronize];
}

- (BOOL) shouldUpdateAuthorization:(NSDictionary*)dict {
    // If no receipt - NO
    NSURL *URL = [NSBundle mainBundle].appStoreReceiptURL;
    NSString *path = URL.path;
    const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil];
    if (!exists) {
        return NO;
    }

    // There's receipt but no authorization dictionary - YES
    if(!dict) {
        return YES;
    }

    // Receipt file size has changed since last check - YES
    NSNumber* appReceiptFileSize = nil;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:nil];
    NSNumber* dictAppReceiptFileSize = [dict objectForKey:kAppReceiptFileSize];
    if ([appReceiptFileSize unsignedIntValue] != [dictAppReceiptFileSize unsignedIntValue]) {
        return YES;
    }

    // If user has an active authorization for date - NO
    if ([self hasActiveAuthorizationForDate:[NSDate date] inDict:dict]) {
        return NO;
    }

    // else we have an expired subscription
    NSArray *pending_renewal_info = [dict objectForKey:kPendingRenewalInfo];

    // If expired and pending renewal info is missing - we are
    if(!pending_renewal_info) {
        return YES;
    }

    // If expired but user's last known intention was to auto-renew - YES
    if([pending_renewal_info count] == 1 && [pending_renewal_info[0] isKindOfClass:[NSDictionary class]]) {
        NSString *auto_renew_status = [pending_renewal_info[0] objectForKey:kAutoRenewStatus];
        if (auto_renew_status && [auto_renew_status isEqualToString:@"1"]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL) hasActiveAuthorizationForDate:(NSDate*) date inDict:(NSDictionary*) dict {
    if(!dict) {
        return NO;
    }

    NSDate *authExpires = [dict objectForKey:kAuthorizationExpires];

    if(authExpires && [date compare:authExpires] != NSOrderedDescending) {
        return YES;
    }
    return NO;
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

    // Authorizations
    NSDictionary *authDict = [self authorizationDictionary];
    if (authDict) {
        NSString *authorizationString = authDict[kSignedAuthorization];
        if ([authorizationString length]) {
            mutableConfigCopy[@"Authorizations"] = [[NSArray alloc] initWithObjects:authorizationString, nil];
        }
    }

    // SponsorId override
    if(self.startTunnelSubscriptionState != PsiphonSubscriptionStateNotSubscribed) {
        NSDictionary *readOnlySubscriptionConfig = readOnly[@"subscriptionConfig"];
        if(readOnlySubscriptionConfig && readOnlySubscriptionConfig[@"SponsorId"]) {
            mutableConfigCopy[@"SponsorId"] = readOnlySubscriptionConfig[@"SponsorId"];
        }
    }

    currentSponsorId = mutableConfigCopy[@"SponsorId"];

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
    [notifier post:@"NE.tunnelConnected"];
    [self tryStartVPN];
    [self trySubscriptionCheck];
}

- (void)onServerTimestamp:(NSString * _Nonnull)timestamp {
	[sharedDB updateServerTimestamp:timestamp];

    // Check if user has an active subscription in the device's time
    // If NO - do nothing
    // If YES - proceed with checking the subscription against server timestamp
    NSDictionary* dict = [self authorizationDictionary];
    if([self hasActiveAuthorizationForDate:[NSDate date] inDict:dict]) {
        // The following code adapted from
        // https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/DataFormatting/Articles/dfDateFormatting10_4.html
        NSDateFormatter *rfc3339DateFormatter = [NSDateFormatter createRFC3339Formatter];

        NSString *serverTimestamp = [sharedDB getServerTimestamp];
        NSDate *serverDate = [rfc3339DateFormatter dateFromString:serverTimestamp];
        if (serverDate != nil) {
            if(![self hasActiveAuthorizationForDate:serverDate inDict:dict]) {
                // User is possibly cheating, terminate the app due to 'Bad Clock'.
                [self killExtensionForBadClock];
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

    [self displayMessage:alertDisplayMessage];
}

@end
