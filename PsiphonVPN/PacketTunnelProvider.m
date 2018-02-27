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
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <stdatomic.h>
#import "PacketTunnelProvider.h"
#import "PsiphonConfigFiles.h"
#import "PsiphonConfigUserDefaults.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "Logging.h"
#import "Subscription.h"
#import "PacketTunnelUtils.h"
#import "Authorizations.h"
#import "NSDateFormatter+RFC3339.h"
#import "NSError+Convenience.h"
#import "RACSignal+Operations.h"
#import "RACDisposable.h"
#import "RACTuple.h"
#import "RACSignal+Operations2.h"
#import "RACScheduler.h"
#import <ReactiveObjC/RACSubject.h>
#import <ReactiveObjC/RACReplaySubject.h>

NSErrorDomain _Nonnull const PsiphonTunnelErrorDomain = @"PsiphonTunnelErrorDomain";


typedef NS_ENUM(NSInteger, AuthorizationTokenActivity) {
    AuthorizationTokenInactive,
    AuthorizationTokenActiveOrEmpty
};

typedef NS_ENUM(NSInteger, GracePeriodState) {
    /** @const GracePeriodStateInactive The extension is not in grace period. */
    GracePeriodStateInactive,
    /** @const GracePeriodActive Grace period is active, and the grace period timer will start after user presses Done on the grace period message shown to them. */
    GracePeriodStateActive,
    /** @const GracePeriodDone Grace period timer is done, subscription check needs to be performed to reset grace period state. */
    GracePeriodStateDone
};

@interface PacketTunnelProvider ()

@property (atomic) BOOL extensionIsZombie;

@property (nonatomic) SubscriptionState *subscriptionCheckState;

// Start vpn decision. If FALSE, VPN should not be activated, even though Psiphon tunnel might be connected.
// shouldStartVPN SHOULD NOT be altered after it is set to TRUE.
@property (atomic) BOOL shouldStartVPN;

@property (nonatomic) GracePeriodState gracePeriodState;

@end

@implementation PacketTunnelProvider {

    PsiphonTunnel *psiphonTunnel;

    PsiphonDataSharedDB *sharedDB;

    Notifier *notifier;

    _Atomic BOOL showUpstreamProxyErrorMessage;

    // An infinite signal that emits Psiphon tunnel connection state.
    // When subscribed, replays the last known connection state.
    RACReplaySubject<NSNumber *> *tunnelConnectionStateSubject;

    // An infinite signal that emits @(AuthorizationTokenInactive) if the subscription authorization token was invalid,
    // and @(AuthorizationTokenActiveOrEmpty) if it was valid (or non-existent).
    // When subscribed, replays the last item this subject was sent by onActiveAuthorizationIDs callback.
    RACReplaySubject<NSNumber *> *subscriptionAuthorizationTokenActiveSubject;

    RACDisposable *subscriptionDisposable;
}

- (id)init {
    self = [super init];
    if (self) {
        // Create our tunnel instance
        psiphonTunnel = [PsiphonTunnel newPsiphonTunnel:(id <TunneledAppDelegate>) self];

        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        atomic_init(&self->showUpstreamProxyErrorMessage, TRUE);

        _extensionIsZombie = FALSE;
        _subscriptionCheckState = nil;
        _shouldStartVPN = FALSE;
        _gracePeriodState = GracePeriodStateInactive;
    }
    return self;
}

- (void)initSubscriptionCheckSubjects {
    self->tunnelConnectionStateSubject = [RACReplaySubject replaySubjectWithCapacity:1];
    self->subscriptionAuthorizationTokenActiveSubject = [RACReplaySubject replaySubjectWithCapacity:1];
}

- (void)forceSubscriptionCheck {
    // Bootstraps the signals if they were not initialized already (i.e. the tunnel started with
    // the PsiphonSubscriptionStateNotSubscribed state).
    if (!self->tunnelConnectionStateSubject && !self->subscriptionAuthorizationTokenActiveSubject) {
        [self initSubscriptionCheckSubjects];
    }

    // Sends current connection status to the tunnelConnectionStateSubject subject.
    [self->tunnelConnectionStateSubject sendNext:@([psiphonTunnel getConnectionState])];

    // Since no subscription token was passed (otherwise tunnel would start with a different subscription state)
    // We can send AuthorizationTokenActiveOrEmpty to subscriptionAuthorizationTokenActiveSubject subject.
    [self->subscriptionAuthorizationTokenActiveSubject sendNext:@(AuthorizationTokenActiveOrEmpty)];

    [self checkSubscription];
}

// Initializes ReactiveObjC signals for subscription check and subscribes to them.
// This method shouldn't be called if no subscription check is necessary.
//
// While the subscription process is ongoing, the extension's subscriptionCheckState is set to in-progress.
// Once subscription check is finished, subscriptionCheckState is set to the appropriate state:
//
- (void)checkSubscription {

    __weak PacketTunnelProvider *weakSelf = self;

    // Dispose of ongoing subscription check if any.
    [subscriptionDisposable dispose];

    void (^handleExpiredSubscription)(void) = ^{
        LOG_DEBUG_NOTICE(@"subscription expired restarting tunnel");

        if (weakSelf.extensionStartMethod == ExtensionStartMethodFromContainer) {

            // Restarts the tunnel to re-connect with the correct sponsor ID.
            [weakSelf.subscriptionCheckState setStateNotSubscribed];
            [weakSelf restartTunnel];

        } else {

            // subscriptionCheckState should not be changed from inProgress, until the grace period expires
            // and another subscription check happens.

            if (self.gracePeriodState == GracePeriodStateDone) {
                LOG_DEBUG_NOTICE(@"grace period done killing extension for expired subscription");
                [self killExtensionForExpiredSubscription];
            } else {
                [self startGracePeriod];
            }
        }
    };

    // tunnelConnectedSignal is an infinite signal that emits an item whenever Psiphon tunnel is connected.
    RACSignal *tunnelConnectedSignal = [self->tunnelConnectionStateSubject
      filter:^BOOL(NSNumber *x) {
        return (PsiphonConnectionState)[x integerValue] == PsiphonConnectionStateConnected;
    }];

    // activeLocalSubscriptionCheckSignal is a finite signal that emits one of SubscriptionCheckEnum enums.
    // This signal combines information from local subscription check and information received from the tunnel,
    // to determine how the subscription check should be performed. (i.e. does remote server need to be contacted).
    RACSignal<NSNumber *> *activeLocalSubscriptionCheckSignal = [[self->subscriptionAuthorizationTokenActiveSubject
      take:1]
      flattenMap:^RACSignal *(NSNumber *subscriptionTokenValidity) {
          if ([subscriptionTokenValidity integerValue] == AuthorizationTokenInactive) {
              // Previous subscription token sent is not active, should contact subscription server.
              return [RACSignal return:@(SubscriptionCheckShouldUpdateToken)];
          } else {
              // Either no subscription authorization token was passed or it was valid.
              return [Subscription localSubscriptionCheck];
          }
      }];


#if DEBUG
    const int networkRetryCount = 3;
#else
    const int networkRetryCount = 6;
#endif

    // updateSubscriptionTokenSignal is a finite signal that emits two items of type SubscriptionResultModel.
    // When the signal is subscribed to it immediately emits SubscriptionResultModel with inProgress set to TRUE,
    // the subscriber should set the correct internal state following
    RACSignal *updateSubscriptionTokenSignal = [[[[[self subscriptionReceiptUnlocked]
      flattenMap:^RACSignal *(id nilValue) {
          // Emits an item when Psiphon tunnel is connected and VPN is started.
          LOG_DEBUG_NOTICE(@"subscription receipt is readable");
          return [self.vpnStartedSignal zipWith:[tunnelConnectedSignal take:1]];
      }]
      flattenMap:^RACSignal *(id nilValue) {
          // After VPN started and Psiphon is connected, returns a signal that emits an item
          // if Subscription authorization token needs to be updated.
          return activeLocalSubscriptionCheckSignal;
      }]
      flattenMap:^RACSignal *(NSNumber *subscriptionCheckObject) {

          switch ((SubscriptionCheckEnum) [subscriptionCheckObject integerValue]) {
              case SubscriptionCheckTokenExpired:
                  return [RACSignal return:[SubscriptionResultModel failed:SubscriptionResultErrorExpired]];

              case SubscriptionCheckHasActiveToken:
                  return [RACSignal return:[SubscriptionResultModel success:nil receiptFilSize:nil]];

              case SubscriptionCheckShouldUpdateToken:
                  // Emits an item whose value is the dictionary returned from the subscription verifier server,
                  // emits an error on all errors.
                  LOG_DEBUG_NOTICE(@"requesting new subscription authorization token");
                  return [[[[SubscriptionVerifierService updateSubscriptionAuthorizationTokenFromRemote]
                    retryWhen:^RACSignal *(RACSignal *errors) {
                        return [[errors
                          zipWith:[RACSignal rangeStartFrom:1 count:networkRetryCount]]
                          flattenMap:^RACSignal *(RACTwoTuple<NSError *, NSNumber *> *retryCountTuple) {
                              // Emits the error on the last retry.
                              if ([retryCountTuple.second integerValue] == networkRetryCount) {
                                  return [RACSignal error:retryCountTuple.first];
                              }
                              // Exponential backoff.
                              return [RACSignal timer:pow(4, [retryCountTuple.second integerValue])];
                          }];
                    }]
                    map:^SubscriptionResultModel *(RACTwoTuple<NSDictionary *, NSNumber *> *response) {
                        // Wraps the response in SubscriptionResultModel.
                        return [SubscriptionResultModel success:response.first receiptFilSize:response.second];
                    }]
                    catch:^RACSignal *(NSError *error) {
                        // Return SubscriptionResultModel for PsiphonReceiptValidationErrorInvalidReceipt error code.
                        if ([error.domain isEqualToString:ReceiptValidationErrorDomain]) {
                            if (error.code == PsiphonReceiptValidationErrorInvalidReceipt) {
                                return [RACSignal return:[SubscriptionResultModel failed:SubscriptionResultErrorInvalidReceipt]];
                            }
                        }
                        // Else re-emit the error.
                        return [RACSignal error:error];
                    }];

              default:
                  LOG_ERROR(@"unhandled subscription check value %@", subscriptionCheckObject);
                  abort();
          }
      }]
      startWith:[SubscriptionResultModel inProgress]];

    // Subscribes to the updateSubscriptionTokenSignal signal.
    // Subscription methods should always get called from the main thread.
    subscriptionDisposable = [[updateSubscriptionTokenSignal
      deliverOnMainThread]
      subscribeNext:^(SubscriptionResultModel *result) {

          if (result.inProgress) {
              // Subscription check is in progress.
              // Sets extension's subscription status to in progress.

              LOG_DEBUG_NOTICE(@"subscription check in progress");
              [weakSelf.subscriptionCheckState setStateInProgress];
              return;
          }

          if (!result.remoteAuthDict && !result.error) {
              // Subscription check finished, current subscription token is active,
              // no remote check was necessary.

              LOG_DEBUG_NOTICE(@"subscription is active no remote check done");
              [weakSelf.subscriptionCheckState setStateSubscribed];
              return;
          }

          if (result.error) {
              // Subscription check finished with error.

              switch (result.error.code) {
                  case SubscriptionResultErrorInvalidReceipt:
                      [weakSelf killExtensionForInvalidReceipt];
                      break;

                  case SubscriptionResultErrorExpired:
                      handleExpiredSubscription();
                      break;

                  default:
                      LOG_ERROR(@"unhandled subscription result error code %ld", (long) result.error.code);
                      abort();
                      break;
              }
              return;
          }

          // At this point, subscription check finished and received response
          // from the subscription verifier server.

          NSString *tunnelAuthTokenID;

          // Updates subscription and persists subscription.
          Subscription *subscription = [Subscription fromPersistedDefaults];

          // Keep a copy of the token passed to the tunnel previously.
          // This token represents the authorization token accepted by the Psiphon server,
          // regardless of what token was passed to the server.
          tunnelAuthTokenID = [subscription.authorizationToken.ID copy];

          subscription.appReceiptFileSize = result.submittedReceiptFileSize;
          NSError *error = [subscription updateSubscriptionWithRemoteAuthDict:result.remoteAuthDict];
          if (error) {
              LOG_ERROR(@"failed to update with subscription remote auth dict:%@", error);
              return;
          }
          [subscription persistChanges];

          LOG_DEBUG_NOTICE(@"subscription callback time:%@", [NSDate date]);
          LOG_DEBUG_NOTICE(@"subscription server token expiry:%@", subscription.authorizationToken.expires);

          // Extract request date from the response and convert to NSDate.
          NSDate *requestDate = nil;
          NSString *requestDateString = (NSString *) result.remoteAuthDict[kRemoteSubscriptionVerifierRequestDate];
          if ([requestDateString length]) {
              requestDate = [[NSDateFormatter sharedRFC3339DateFormatter] dateFromString:requestDateString];
          }

          // Bad Clock error if user has an active subscription in server time
          // but in device time it appears to be expired.
          if (requestDate) {
              if ([subscription hasActiveSubscriptionTokenForDate:requestDate]
                && ![subscription hasActiveSubscriptionTokenForDate:[NSDate date]]) {
                  [self killExtensionForBadClock];
                  return;
              }
          }

          if (subscription.authorizationToken) {

              // New authorization token was received from the subscription verifier server.
              // Restarts the tunnel to connect with the new token only if it is different from
              // the token in use by the tunnel.
              if (![subscription.authorizationToken.ID isEqualToString:tunnelAuthTokenID]) {

                  if (self.gracePeriodState == GracePeriodStateDone) {
                      // Grace period has finished, and subscription check finished successfully
                      // with a new token.
                      // Resets grace period state.
                      self.gracePeriodState = GracePeriodStateInactive;
                  }

                  [weakSelf.subscriptionCheckState setStateSubscribed];
                  [weakSelf restartTunnel];
              }
          } else {
              // Server returned no authorization token, treats this as if subscription was expired.
              handleExpiredSubscription();
          }

      }
      error:^(NSError *error) {
          LOG_ERROR(@"subscription verifier error: %@, %ld", error.localizedDescription, (long)error.code);

          // Schedules another subscription check in 3 hours.
          const int64_t secs_in_3_hours = 3 * 60 * 60;
          dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, secs_in_3_hours * NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{
                [weakSelf checkSubscription];
            });

          // Cleanup.
          [subscriptionDisposable dispose];
          subscriptionDisposable = nil;
      }
      completed:^{
          LOG_DEBUG_NOTICE(@"updateSubscriptionTokenSignal finished");
          // Cleanup.
          [subscriptionDisposable dispose];
          subscriptionDisposable = nil;
      }];
}

- (void)startTunnelWithErrorHandler:(void (^_Nonnull)(NSError *_Nonnull error))errorHandler {

    LOG_DEBUG_NOTICE();

    // VPN should only start if it is started from the container app directly,
    // OR if the user possibly has a valid subscription
    // OR if the extension is started after boot but before being unlocked.

    // Initializes uninitialized properties.
    Subscription *subscription = [Subscription fromPersistedDefaults];
    self.subscriptionCheckState = [SubscriptionState initialStateFromSubscription:subscription];

    LOG_DEBUG_NOTICE(@"starting tunnel with state %@", [self.subscriptionCheckState textDescription]);

    if (self.extensionStartMethod == ExtensionStartMethodFromContainer
        || [self.subscriptionCheckState isSubscribedOrInProgress]) {

        // Listen for messages from the container
        [self listenForContainerMessages];

        if ([self.subscriptionCheckState isSubscribedOrInProgress]) {
            
            [self initSubscriptionCheckSubjects];

            // If there maybe a valid subscription, there is no need to wait
            // for the container to send "M.startVPN" signal.
            self.shouldStartVPN = TRUE;
        }

        __weak PsiphonTunnel *weakPsiphonTunnel = psiphonTunnel;

        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *_Nullable error) {

            if (error != nil) {
                LOG_ERROR(@"setTunnelNetworkSettings failed: %@", error);
                errorHandler([NSError errorWithDomain:PsiphonTunnelErrorDomain code:PsiphonTunnelErrorBadConfiguration]);
                return;
            }

            // Starts Psiphon tunnel.
            BOOL success = [weakPsiphonTunnel start:FALSE];

            if (!success) {
                LOG_ERROR(@"tunnel start failed");
                errorHandler([NSError errorWithDomain:PsiphonTunnelErrorDomain code:PsiphonTunnelErrorInternalError]);
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

        [self displayRepeatingZombieAlert];
    }
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason {
    // Always log the stop reason.
    LOG_ERROR(@"Tunnel stopped. Reason: %ld %@", (long)reason, [PacketTunnelUtils textStopReason:reason]);

    // Cleanup.
    [subscriptionDisposable dispose];
    
    [psiphonTunnel stop];
}

- (void)restartTunnel {
    [psiphonTunnel stop];

    if (![psiphonTunnel start:FALSE]) {
        LOG_ERROR(@"tunnel start failed");
    }
}

- (void)displayMessageAndKillExtension:(NSString *)message {
    LOG_ERROR(@"killing extension due %@", message);

    // Stop the Psiphon tunnel immediately.
    [psiphonTunnel stop];

    [self displayMessage:message completionHandler:^(BOOL success) {
        // Exit only after the user has clicked OK button.
        exit(1);
    }];
}

#pragma mark - Query methods

- (BOOL)isNEZombie {
    return self.extensionIsZombie;
}

- (BOOL)isTunnelConnected {
    return [psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected;
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

// Starts VPN and notifies the container of homepages (if any) when
// `self.shouldStartVPN` is TRUE or the container is in the foreground.
- (BOOL)tryStartVPN {
    if (self.shouldStartVPN || [sharedDB getAppForegroundState]) {
        if ([psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {
            self.reasserting = FALSE;
            [self startVPN];
            [notifier post:NOTIFIER_NEW_HOMEPAGES];
            return TRUE;
        }
    }
    return FALSE;
}

- (void)listenForContainerMessages {
    // The notifier callbacks are always called on the main thread.

    [notifier listenForNotification:NOTIFIER_START_VPN listener:^{
        // If the tunnel is connected, starts the VPN.
        // Otherwise, should establish the VPN after onConnected has been called.
        self.shouldStartVPN = TRUE; // This should be set before calling tryStartVPN.
        [self tryStartVPN];
    }];

    [notifier listenForNotification:NOTIFIER_APP_DID_ENTER_BACKGROUND listener:^{
        // If the VPN start message ("M.startVPN") has not been received from the container,
        // and the container goes to the background, then alert the user to open the app.
        //
        // Note: We expect the value of shouldStartVPN to not be altered after it is set to TRUE.
        if (!self.shouldStartVPN) {
            [self displayMessage:NSLocalizedStringWithDefaultValue(@"OPEN_PSIPHON_APP", nil, [NSBundle mainBundle], @"Please open Psiphon app to finish connecting.", @"Alert message informing the user they should open the app to finish connecting to the VPN. DO NOT translate 'Psiphon'.")];
        }
    }];

    [notifier listenForNotification:NOTIFIER_FORCE_SUBSCRIPTION_CHECK listener:^{
        // Container received a new subscription transaction.
        [self forceSubscriptionCheck];
    }];
}

#pragma mark - Subscription

// A finite signal that emits an item when device is unlocked.
- (RACSignal *)subscriptionReceiptUnlocked {
#if DEBUG
    const NSTimeInterval retryInterval = 5; // 5 seconds.
#else
    const NSTimeInterval retryInterval = 5 * 60; // 5 minutes.
#endif

    // Leeway of 5 seconds added in the interest of system performance / power consumption.
    const NSTimeInterval leeway = 5; // 5 seconds.

    return [[[[RACSignal interval:retryInterval onScheduler:[RACScheduler mainThreadScheduler] withLeeway:leeway]
      startWith:nil]
      skipWhileBlock:^BOOL(id x) {
          LOG_DEBUG_NOTICE(@"check if device is locked");
          return [self isDeviceLocked];
      }]
      // take:1 on an infinite signal, effectively turns it into a finite signal after it emits its first item.
      take:1];
}

/*!
 * Shows "subscription expired" alert to the user.
 * This alert will only be shown again after a time interval after the user *dismisses* the current alert.
 */
- (void)displayRepeatingZombieAlert {
    const int64_t intervalSec = 60; // Every minute.

    [self displayMessage:
        NSLocalizedStringWithDefaultValue(@"CANNOT_START_TUNNEL_DUE_TO_SUBSCRIPTION", nil, [NSBundle mainBundle], @"Your Psiphon subscription has expired.\nSince you're not a subscriber or your subscription has expired, Psiphon can only be started from the Psiphon app.\n\nPlease open the Psiphon app.", @"Alert message informing user that their subscription has expired or that they're not a subscriber, therefore Psiphon can only be started from the Psiphon app. DO NOT translate 'Psiphon'.")
       completionHandler:^(BOOL success) {
           // If the user dismisses the message, show the alert again in intervalSec seconds.
           if (success) {
               dispatch_after(dispatch_time(DISPATCH_TIME_NOW, intervalSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                   [self displayRepeatingZombieAlert];
               });
           }
       }];
}

- (void)startGracePeriod {

    if (self.gracePeriodState != GracePeriodStateInactive) {
        return;
    }

    self.gracePeriodState = GracePeriodStateActive;

#if DEBUG
    int64_t gracePeriodSec = 2 * 60; // 2 minutes.
#else
    int64_t gracePeriodSec = 1 * 60 * 60;  // 1 hour.
#endif
    __weak PacketTunnelProvider *weakSelf = self;

    // User doesn't have an active subscription. Notify them, after making sure they've checked
    // the notification we will start an hour of extra grace period.
    // NOTE: Waits for the user to acknowledge the message before starting the extra grace period.
    [self displayMessage:NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_EXPIRED_WILL_KILL_TUNNEL", nil, [NSBundle mainBundle], @"Your Psiphon subscription has expired. Psiphon will stop automatically in an hour if subscription is not renewed. Open the Psiphon app to review your subscription to continue using premium features.", @"Alert message informing user that their subscription has expired, and that Psiphon will stop in an hour if subscription is not renewed. Do not translate 'Psiphon'.")
       completionHandler:^(BOOL success) {

           if (!success) {
               LOG_ERROR(@"iOS was unable to display subscription grace period starting message");
               return;
           }

           dispatch_after(dispatch_walltime(NULL, gracePeriodSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
               LOG_DEBUG_NOTICE(@"grace period expired checking subscription");
               weakSelf.gracePeriodState = GracePeriodStateDone;
               [self checkSubscription];
           });
       }];
}

- (void)killExtensionForExpiredSubscription {
    NSString *message = NSLocalizedStringWithDefaultValue(@"TUNNEL_KILLED", nil, [NSBundle mainBundle], @"Psiphon has been stopped automatically since your subscription has expired.", @"Alert message informing user that Psiphon has been stopped automatically since the subscription has expired. Do not translate 'Psiphon'.");
    [self displayMessageAndKillExtension:message];
}

- (void)killExtensionForBadClock {
    NSString *message = NSLocalizedStringWithDefaultValue(@"BAD_CLOCK_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"We've detected the time on your device is out of sync with your time zone. Please update your clock settings and restart the app", @"Alert message informing user that the device clock needs to be updated with current time");
    [self displayMessageAndKillExtension:message];
}

- (void)killExtensionForInvalidReceipt {
    NSString *message = NSLocalizedStringWithDefaultValue(@"BAD_RECEIPT_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"Your subscription receipt can not be verified, please refresh it and try again.", @"Alert message informing user that subscription receipt can not be verified");
    [self displayMessageAndKillExtension:message];
}

- (void)displayCorruptSettingsFileMessage {
    NSString *message = NSLocalizedStringWithDefaultValue(@"CORRUPT_SETTINGS_MESSAGE", nil, [NSBundle mainBundle], @"Your app settings file appears to be corrupt. Try reinstalling the app to repair the file.", @"Alert dialog message informing the user that the settings file in the app is corrupt, and that they can potentially fix this issue by re-installing the app.");
    [self displayMessage:message];
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
    return [PsiphonConfigFiles embeddedServerEntriesPath];
}

- (NSString * _Nullable)getPsiphonConfig {

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *bundledConfigPath = [PsiphonConfigFiles psiphonConfigPath];

    if (![fileManager fileExistsAtPath:bundledConfigPath]) {
        LOG_ERROR(@"Config file not found. Aborting now.");
        [self displayCorruptSettingsFileMessage];
        abort();
    }

    // Read in psiphon_config JSON
    NSData *jsonData = [fileManager contentsAtPath:bundledConfigPath];
    NSError *err = nil;
    NSDictionary *readOnly = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&err];

    if (err) {
        LOG_ERROR(@"%@", [NSString stringWithFormat:@"Aborting. Failed to parse config JSON: %@", err.description]);
        [self displayCorruptSettingsFileMessage];
        abort();
    }

    NSMutableDictionary *mutableConfigCopy = [readOnly mutableCopy];

    // Applying mutations to config
    NSNumber *fd = (NSNumber*)[[self packetFlow] valueForKeyPath:@"socket.fileDescriptor"];

    // In case of duplicate keys, value from psiphonConfigUserDefaults
    // will replace mutableConfigCopy value.
    PsiphonConfigUserDefaults *psiphonConfigUserDefaults = [[PsiphonConfigUserDefaults alloc]
      initWithSuiteName:APP_GROUP_IDENTIFIER];
    [mutableConfigCopy addEntriesFromDictionary:[psiphonConfigUserDefaults dictionaryRepresentation]];

    mutableConfigCopy[@"PacketTunnelTunFileDescriptor"] = fd;

    mutableConfigCopy[@"ClientVersion"] = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];


    NSMutableArray *authorizationTokens = [NSMutableArray array];

    // Add subscription tokens
    Subscription *subscription = [Subscription fromPersistedDefaults];
    if (subscription.authorizationToken) {
        [authorizationTokens addObject:subscription.authorizationToken.base64Representation];
    }

    if ([authorizationTokens count] > 0) {
        mutableConfigCopy[@"Authorizations"] = [authorizationTokens copy];
    }

    // SponsorId override
    if ([self.subscriptionCheckState isSubscribedOrInProgress]) {
        NSDictionary *readOnlySubscriptionConfig = readOnly[@"subscriptionConfig"];
        if(readOnlySubscriptionConfig && readOnlySubscriptionConfig[@"SponsorId"]) {
            mutableConfigCopy[@"SponsorId"] = readOnlySubscriptionConfig[@"SponsorId"];
        }
    }

    jsonData = [NSJSONSerialization dataWithJSONObject:mutableConfigCopy
      options:0 error:&err];

    if (err) {
        LOG_ERROR(@"Aborting. Failed to create JSON data from config object: %@", err);
        [self displayCorruptSettingsFileMessage];
        abort();
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)onConnectionStateChangedFrom:(PsiphonConnectionState)oldState to:(PsiphonConnectionState)newState {
    [self->tunnelConnectionStateSubject sendNext:@(newState)];
}

- (void)onConnecting {
    LOG_DEBUG(@"onConnecting");
    self.reasserting = TRUE;
}

- (void)onActiveAuthorizationIDs:(NSArray * _Nonnull)authorizationIds {

    // It is assumed that the subscription info at this point is the same as the subscription info
    // passed in getPsiphonConfig callback.
    Subscription *subscription = [Subscription fromPersistedDefaults];
    if (subscription.authorizationToken && ![authorizationIds containsObject:subscription.authorizationToken.ID]) {

        // Remove persisted token.
        subscription.authorizationToken = nil;
        [subscription persistChanges];

        // Send value AuthorizationTokenInactive if subscription authorization token was invalid.
        [self->subscriptionAuthorizationTokenActiveSubject sendNext:@(AuthorizationTokenInactive)];

    } else {

        // Send value AuthorizationTokenActiveOrEmpty if subscription authorization token was not invalid (i.e. token is non-existent or valid)
        [self->subscriptionAuthorizationTokenActiveSubject sendNext:@(AuthorizationTokenActiveOrEmpty)];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.subscriptionCheckState isSubscribedOrInProgress]) {
            [self checkSubscription];
        }
    });
}

- (void)onConnected {
    LOG_DEBUG_NOTICE(@"onConnected with subscription status %@", [self.subscriptionCheckState textDescription]);
    [notifier post:NOTIFIER_TUNNEL_CONNECTED];
    [self tryStartVPN];
}

- (void)onServerTimestamp:(NSString * _Nonnull)timestamp {
	[sharedDB updateServerTimestamp:timestamp];

    NSDate *serverDate = [[NSDateFormatter sharedRFC3339DateFormatter] dateFromString:timestamp];

    // Check if user has an active subscription in the device's time
    // If NO - do nothing
    // If YES - proceed with checking the subscription against server timestamp
    Authorizations *authorizations = [Authorizations fromPersistedDefaults];
    Subscription *subscription = [Subscription fromPersistedDefaults];
    if ([authorizations hasActiveAuthorizationTokenForDate:[NSDate date]]) {
        // The following code adapted from
        // https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/DataFormatting/Articles/dfDateFormatting10_4.html
        if (serverDate != nil) {
            if (![authorizations hasActiveAuthorizationTokenForDate:serverDate]) {
                // User is possibly cheating, terminate extension due to 'Bad Clock'.
                [self killExtensionForBadClock];
            }
        }
    }

    if ([subscription hasActiveSubscriptionTokenForDate:[NSDate date]]) {
        if (serverDate != nil) {
            if (![subscription hasActiveSubscriptionTokenForDate:serverDate]) {
                // User is possibly cheating, terminate extension due to 'Bad Clock'.
                [self killExtensionForBadClock];
            }
        }
    }
}

- (void)onAvailableEgressRegions:(NSArray *)regions {
    [sharedDB insertNewEgressRegions:regions];

    // Notify container
    [notifier post:NOTIFIER_ON_AVAILABLE_EGRESS_REGIONS];
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
