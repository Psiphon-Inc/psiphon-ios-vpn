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
#import "Subscription.h"
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
#import "RACSignal.h"
#import "RACUnit.h"
#import <ReactiveObjC/RACSubject.h>
#import <ReactiveObjC/RACReplaySubject.h>

NSErrorDomain _Nonnull const PsiphonTunnelErrorDomain = @"PsiphonTunnelErrorDomain";

PsiFeedbackLogType const SubscriptionCheckLogType = @"SubscriptionCheck";
PsiFeedbackLogType const ExtensionNotificationLogType = @"ExtensionNotification";
PsiFeedbackLogType const PacketTunnelProviderLogType = @"PacketTunnelProvider";
PsiFeedbackLogType const ExitReasonLogType = @"ExitReason";

/** Status of subscription authorization included in Psiphon config. */
typedef NS_ENUM(NSInteger, SubscriptionAuthorizationStatus) {
    /** @const SubscriptionAuthorizationStatusRejected Authorization was rejected by Psiphon. */
    SubscriptionAuthorizationStatusRejected,
    /** @const SubscriptionAuthorizationStatusActiveOrEmpty Authorization was either accepted by Psiphon, or no authorization was sent. */
    SubscriptionAuthorizationStatusActiveOrEmpty
};

/** Extension's grace period state. */
typedef NS_ENUM(NSInteger, GracePeriodState) {
    /** @const GracePeriodStateInactive The extension is not in grace period. */
    GracePeriodStateInactive,
    /** @const GracePeriodActive Grace period is active, and the grace period timer will start after user presses Done on the grace period message shown to them. */
    GracePeriodStateActive,
    /** @const GracePeriodDone Grace period timer is done, subscription check needs to be performed to reset grace period state. */
    GracePeriodStateDone
};

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

@property (nonatomic) SubscriptionState *subscriptionCheckState;

// Start vpn decision. If FALSE, VPN should not be activated, even though Psiphon tunnel might be connected.
// shouldStartVPN SHOULD NOT be altered after it is set to TRUE.
@property (atomic) BOOL shouldStartVPN;

@property (nonatomic) GracePeriodState gracePeriodState;

@property (nonatomic) PsiphonTunnel *psiphonTunnel;

// Authorization IDs supplied to tunnel-core from the container.
// NOTE: Does not include subscription authorization ID.
@property (atomic) NSSet<NSString *> *suppliedContainerAuthorizationIDs;

@property (nonatomic) PsiphonConfigSponsorIds *cachedSpondorIDs;

@end

@implementation PacketTunnelProvider {

    _Atomic BOOL showUpstreamProxyErrorMessage;

    // Serial queue of work to be done following callbacks from PsiphonTunnel.
    dispatch_queue_t workQueue;

    // Scheduler to be used by AppStore subscription check code.
    // NOTE: RACScheduler objects are all serial schedulers and cheap to create.
    //       The underlying implementation creates a GCD dispatch queues.
    RACScheduler *subscriptionScheduler;

    // An infinite signal that emits Psiphon tunnel connection state.
    // When subscribed, replays the last known connection state.
    // @scheduler Events are delivered on some background system thread.
    RACReplaySubject<NSNumber *> *tunnelConnectionStateSubject;

    // An infinite signal that emits @(SubscriptionAuthorizationStatusRejected) if the subscription authorization
    // was invalid, and @(SubscriptionAuthorizationStatusActiveOrEmpty) if it was valid (or non-existent).
    // When subscribed, replays the last item this subject was sent by onActiveAuthorizationIDs callback.
    RACReplaySubject<NSNumber *> *subscriptionAuthorizationActiveSubject;

    RACDisposable *subscriptionDisposable;

    AppProfiler *appProfiler;
}

- (id)init {
    self = [super init];
    if (self) {
        [AppProfiler logMemoryReportWithTag:@"PacketTunnelProviderInit"];

        atomic_init(&self->showUpstreamProxyErrorMessage, TRUE);

        workQueue = dispatch_queue_create("ca.psiphon.PsiphonVPN.workQueue", DISPATCH_QUEUE_SERIAL);

        _psiphonTunnel = [PsiphonTunnel newPsiphonTunnel:(id <TunneledAppDelegate>) self];

        _tunnelProviderState = TunnelProviderStateInit;
        _subscriptionCheckState = nil;
        _shouldStartVPN = FALSE;
        _gracePeriodState = GracePeriodStateInactive;
    }
    return self;
}

- (void)initSubscriptionCheckObjects {
    self->subscriptionScheduler = [RACScheduler schedulerWithPriority:RACSchedulerPriorityDefault name:@"ca.psiphon.Psiphon.PsiphonVPN.SubscriptionScheduler"];
    self->tunnelConnectionStateSubject = [RACReplaySubject replaySubjectWithCapacity:1];
    self->subscriptionAuthorizationActiveSubject = [RACReplaySubject replaySubjectWithCapacity:1];
}

// scheduleSubscriptionCheck should be used to schedule any subscription check.
// NOTE: This method is thread-safe.
- (void)scheduleSubscriptionCheckWithRemoteCheckForced:(BOOL)remoteCheckForced {

    // Dispose of ongoing subscription check if any.
    [subscriptionDisposable dispose];

    // Bootstraps subjects used by subscription check.
    if (remoteCheckForced) {
        if (self->tunnelConnectionStateSubject) {
            PSIAssert(self->subscriptionAuthorizationActiveSubject);
        } else {
            PSIAssert(!self->subscriptionAuthorizationActiveSubject);
        }

        // Bootstraps the signals if they were not initialized already (i.e. the tunnel started with
        // the PsiphonSubscriptionStateNotSubscribed state).
        if (!self->tunnelConnectionStateSubject && !self->subscriptionAuthorizationActiveSubject) {
            [self initSubscriptionCheckObjects];
        }

        // Bootstraps tunnelConnectionStateSubject by sending current connection status to it.
        [self->tunnelConnectionStateSubject sendNext:@([self.psiphonTunnel getConnectionState])];

        // Bootstraps subscriptionAuthorizationActiveSubject by a item of type SubscriptionAuthorizationStatus to it.
        // The value doesn't matter since the subscription is forced.
        [self->subscriptionAuthorizationActiveSubject sendNext:@(SubscriptionAuthorizationStatusActiveOrEmpty)];
    }

    PSIAssert(self->subscriptionScheduler != nil);

    [self->subscriptionScheduler schedule:^{
        [self checkSubscriptionWithRemoteCheckForced:remoteCheckForced];
    }];

}

// scheduleSubscriptionCheckWithRemoteCheckForced should always be preferred to this method.
//
// Initializes ReactiveObjC signals for subscription check and subscribes to them.
// This method shouldn't be called if no subscription check is necessary.
//
// While the subscription process is ongoing, the extension's subscriptionCheckState is set to in-progress.
// Once subscription check is finished, subscriptionCheckState is set to the appropriate state.
//
// NOTE: This method be invoked only if a subscription check is necessary.
//
- (void)checkSubscriptionWithRemoteCheckForced:(BOOL)remoteCheckForced {
    [AppProfiler logMemoryReportWithTag:@"SubscriptionCheckBegin"];

    PSIAssert(self.subscriptionCheckState != nil);
    PSIAssert(self->subscriptionScheduler == RACScheduler.currentScheduler);
    PSIAssert(self->tunnelConnectionStateSubject != nil);
    PSIAssert(self->subscriptionAuthorizationActiveSubject != nil);

    __weak PacketTunnelProvider *weakSelf = self;

    void (^handleExpiredSubscription)(void) = ^{

        PSIAssert([weakSelf.subscriptionCheckState isInProgress]);

        if (weakSelf.extensionStartMethod == ExtensionStartMethodFromContainer) {

            [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"authorization expired restarting tunnel"];

            // Restarts the tunnel to re-connect with the correct sponsor ID.
            [weakSelf.subscriptionCheckState setStateNotSubscribed];
            [weakSelf reconnectWithConfig:weakSelf.cachedSpondorIDs.defaultSponsorId];

        } else {

            // subscriptionCheckState should not be changed from inProgress, until the grace period expires
            // and another subscription check happens.

            if (self.gracePeriodState == GracePeriodStateDone) {
                [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"grace period finished killing extension"];

                [self killExtensionForExpiredSubscription];
            } else {
                [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"authorization expired starting grace period"];
                [self startGracePeriod];
            }
        }
    };

    // tunnelConnectedSignal is an infinite signal that emits an item whenever Psiphon tunnel is connected.
    RACSignal *tunnelConnectedSignal = [self->tunnelConnectionStateSubject
      filter:^BOOL(NSNumber *x) {
        return [x integerValue] == PsiphonConnectionStateConnected;
    }];

    // subscriptionCheckSignal is a finite signal that emits an item of type SubscriptionCheckEnum.
    // If remoteCheckForced is TRUE, the signal immediately emits an item with value SubscriptionCheckShouldUpdateAuthorization.
    // Otherwise, it combines information from local subscription check and information received from the tunnel,
    // to determine how the subscription check should be performed. (i.e. does remote server need to be contacted).
    //
    RACSignal<NSNumber *> *subscriptionCheckSignal = [[RACSignal return:[NSNumber numberWithBool:remoteCheckForced]]
      flattenMap:^RACSignal *(NSNumber *forceBoolValue) {
          if ([forceBoolValue boolValue]) {
              return [RACSignal return:@(SubscriptionCheckShouldUpdateAuthorization)];
          } else {
              return [[self->subscriptionAuthorizationActiveSubject
                take:1]
                flattenMap:^RACSignal *(NSNumber *authorizationStatus) {
                    if ([authorizationStatus integerValue] == SubscriptionAuthorizationStatusRejected) {
                        // Previous subscription authorization sent is not active, should contact subscription server.
                        return [RACSignal return:@(SubscriptionCheckShouldUpdateAuthorization)];
                    } else {
                        // Either no subscription authorization was passed or it was valid.
                        return [Subscription localSubscriptionCheck];
                    }
                }];
          }
      }];

#if DEBUG
    const int networkRetryCount = 3;
#else
    const int networkRetryCount = 6;
#endif

    // updateSubscriptionAuthorizationSignal is a finite signal that emits two items of type SubscriptionResultModel.
    // When the signal is subscribed to it immediately emits SubscriptionResultModel with inProgress set to TRUE.
    //
    RACSignal *updateSubscriptionAuthorizationSignal = [[[[[self subscriptionReceiptUnlocked]
      flattenMap:^RACSignal *(id nilValue) {
          // Emits an item when Psiphon tunnel is connected and VPN is started.
          [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"receipt is readable"];
          return [self.vpnStartedSignal zipWith:[tunnelConnectedSignal take:1]];
      }]
      flattenMap:^RACSignal *(id nilValue) {
          // After VPN started and Psiphon is connected, returns a signal that emits an item
          // of type SubscriptionCheckEnum.
          return subscriptionCheckSignal;
      }]
      flattenMap:^RACSignal *(NSNumber *subscriptionCheckObject) {

          switch ((SubscriptionCheckEnum) [subscriptionCheckObject integerValue]) {
              case SubscriptionCheckAuthorizationExpired:
                  [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"authorization expired"];
                  return [RACSignal return:[SubscriptionResultModel failed:SubscriptionResultErrorExpired]];

              case SubscriptionCheckHasActiveAuthorization:
                  [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"authorization already active"];
                  return [RACSignal return:[SubscriptionResultModel success:nil receiptFileSize:nil]];

              case SubscriptionCheckShouldUpdateAuthorization:

                  [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"authorization request"];

                  // Emits an item whose value is the dictionary returned from the subscription verifier server,
                  // emits an error on all errors.
                  return [[[[SubscriptionVerifierService updateAuthorizationFromRemote]
                    retryWhen:^RACSignal *(RACSignal *errors) {
                        return [[errors
                          zipWith:[RACSignal rangeStartFrom:1 count:networkRetryCount]]
                          flattenMap:^RACSignal *(RACTwoTuple<NSError *, NSNumber *> *retryCountTuple) {

                              // Emits the error on the last retry.
                              if ([retryCountTuple.second integerValue] == networkRetryCount) {
                                  return [RACSignal error:retryCountTuple.first];
                              }
                              // Exponential backoff.
                              [PsiFeedbackLogger errorWithType:SubscriptionCheckLogType message:@"retry authorization request" object:retryCountTuple.first];

                              return [[RACSignal timer:pow(4, [retryCountTuple.second integerValue])] flattenMap:^RACSignal *(id value) {
                                  // Make sure tunnel is connected before retrying, otherwise terminate subscription chain.
                                  if ([weakSelf.psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {
                                      return [RACSignal return:RACUnit.defaultUnit];
                                  } else {
                                      return [RACSignal error:[NSError errorWithDomain:PsiphonTunnelErrorDomain code:PsiphonTunnelErrorTunnelNotConnected]];
                                  }
                              }];
                          }];
                    }]
                    map:^SubscriptionResultModel *(RACTwoTuple<NSDictionary *, NSNumber *> *response) {
                        // Wraps the response in SubscriptionResultModel.
                        return [SubscriptionResultModel success:response.first receiptFileSize:response.second];
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
                  [PsiFeedbackLogger errorWithType:SubscriptionCheckLogType message:@"unhandled check value %@", subscriptionCheckObject];
                  abort();
          }
      }]
      startWith:[SubscriptionResultModel inProgress]];

    // Subscribes to the updateSubscriptionAuthorizationSignal signal.
    // Subscription methods should always get called from the main thread.
    subscriptionDisposable = [[updateSubscriptionAuthorizationSignal
      subscribeOn:subscriptionScheduler]
      subscribeNext:^(SubscriptionResultModel *result) {

          if (result.inProgress) {
              // Subscription check is in progress.
              // Sets extension's subscription status to in progress.

              [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"started"];
              [weakSelf.subscriptionCheckState setStateInProgress];
              return;
          }

          if (!result.remoteAuthDict && !result.error) {

              // Subscription check finished, current subscription authorization is active,
              // no remote check was necessary.
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
                      [PsiFeedbackLogger errorWithType:SubscriptionCheckLogType message:@"unhandled error code %ld", (long) result.error.code];
                      abort();
                      break;
              }
              return;
          }

          // At this point, subscription check finished and received response
          // from the subscription verifier server.

          @autoreleasepool {

              NSString *currentActiveAuthorization;

              // Updates subscription and persists subscription.
              Subscription *subscription = [Subscription fromPersistedDefaults];

              // Keep a copy of the authorization passed to the tunnel previously.
              // This represents the authorization accepted by the Psiphon server,
              // regardless of what authorization was passed to the server.
              currentActiveAuthorization = [subscription.authorization.ID copy];

              [subscription updateWithRemoteAuthDict:result.remoteAuthDict submittedReceiptFilesize:result.submittedReceiptFileSize];
              [subscription persistChanges];

              [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"received authorization %@ expiring on %@", subscription.authorization.ID,
                  subscription.authorization.expires];

              // Extract request date from the response and convert to NSDate.
              NSDate *requestDate = nil;
              NSString *requestDateString = (NSString *) result.remoteAuthDict[kRemoteSubscriptionVerifierRequestDate];
              if ([requestDateString length]) {
                  requestDate = [NSDate fromRFC3339String:requestDateString];
              }

              // Bad Clock error if user has an active subscription in server time
              // but in device time it appears to be expired.
              if (requestDate) {
                  if ([subscription hasActiveAuthorizationForDate:requestDate]
                    && ![subscription hasActiveAuthorizationForDate:[NSDate date]]) {
                      [self killExtensionForBadClock];
                      return;
                  }
              }

              if (subscription.authorization) {

                  // New authorization was received from the subscription verifier server.
                  // Restarts the tunnel to connect with the new authorization only if it is different from
                  // the authorization in use by the tunnel.
                  if (![subscription.authorization.ID isEqualToString:currentActiveAuthorization]) {

                      if (self.gracePeriodState == GracePeriodStateDone) {
                          // Grace period has finished, and subscription check finished successfully
                          // with a new authorization.
                          // Resets grace period state.
                          self.gracePeriodState = GracePeriodStateInactive;
                      }

                      [weakSelf.subscriptionCheckState setStateSubscribed];
                      [weakSelf reconnectWithConfig:weakSelf.cachedSpondorIDs.subscriptionSponsorId];
                  }
              } else {
                  // Server returned no authorization, treats this as if subscription was expired.
                  handleExpiredSubscription();
              }
          }

      }
      error:^(NSError *error) {
          [AppProfiler logMemoryReportWithTag:@"SubscriptionCheckAuthRequestFailed"];
          [PsiFeedbackLogger errorWithType:SubscriptionCheckLogType message:@"authorization request failed" object:error];

          // No need to retry if the tunnel is not connected.
          if ([error.domain isEqualToString:PsiphonTunnelErrorDomain] && error.code == PsiphonTunnelErrorTunnelNotConnected) {
              return;
          }

          // Schedules another subscription check in 3 hours.
          const int64_t secs_in_3_hours = 3 * 60 * 60;
          dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, secs_in_3_hours * NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{
                [weakSelf scheduleSubscriptionCheckWithRemoteCheckForced:FALSE];
            });

          subscriptionDisposable = nil;
      }
      completed:^{
          [AppProfiler logMemoryReportWithTag:@"SubscriptionCheckCompleted"];
          [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"finished"];
          subscriptionDisposable = nil;
      }];
}

- (void)startTunnelWithErrorHandler:(void (^_Nonnull)(NSError *_Nonnull error))errorHandler {

    // Start app profiling
    if (!appProfiler) {
        appProfiler = [[AppProfiler alloc] init];
        [appProfiler startProfilingWithStartInterval:1 forNumLogs:10 andThenExponentialBackoffTo:60*30 withNumLogsAtEachBackOff:1];
    }

    __weak PacketTunnelProvider *weakSelf = self;

    [[Notifier sharedInstance] registerObserver:self callbackQueue:dispatch_get_main_queue()];

    self.cachedSpondorIDs = [PsiphonConfigReader fromConfigFile].sponsorIds;

    // Initializes uninitialized properties.
    Subscription *subscription = [Subscription fromPersistedDefaults];
    self.subscriptionCheckState = [SubscriptionState initialStateFromSubscription:subscription];

    [PsiFeedbackLogger infoWithType:PacketTunnelProviderLogType
                               json:@{@"StartMethod": [self extensionStartMethodTextDescription],
                                      @"SubscriptionState": [self.subscriptionCheckState textDescription]}];

    // VPN should only start if it is started from the container app directly,
    // or if the user possibly has a valid subscription,
    // or if started due to Connect On Demand rules (or by the user from system Settings) from a crash,
    // or if the extension is started after boot but before being unlocked.
    //
    if (self.extensionStartMethod == ExtensionStartMethodFromContainer ||
        self.extensionStartMethod == ExtensionStartMethodFromCrash ||
        self.subscriptionCheckState.isSubscribedOrInProgress) {

        if ([self.subscriptionCheckState isSubscribedOrInProgress]) {
            
            [self initSubscriptionCheckObjects];

            // If there maybe a valid subscription, there is no need to wait
            // for the container to send "M.startVPN" signal.
            self.shouldStartVPN = TRUE;
        }

        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *_Nullable error) {

            if (error != nil) {
                [PsiFeedbackLogger error:@"setTunnelNetworkSettings failed: %@", error];
                errorHandler([NSError errorWithDomain:PsiphonTunnelErrorDomain code:PsiphonTunnelErrorBadConfiguration]);
                return;
            }

            // Starts Psiphon tunnel.
            BOOL success = [weakSelf.psiphonTunnel start:FALSE];

            if (!success) {
                [PsiFeedbackLogger error:@"tunnel start failed"];
                errorHandler([NSError errorWithDomain:PsiphonTunnelErrorDomain code:PsiphonTunnelErrorInternalError]);
                return;
            }

            weakSelf.tunnelProviderState = TunnelProviderStateStarted;

        }];

    } else {

        // If the user is not a subscriber, or if their subscription has expired
        // we will call startVPN to stop "Connect On Demand" rules from kicking-in over and over if they are in effect.
        //
        // To potentially stop leaking sensitive traffic while in this state, we will route
        // the network to a dead-end by setting tunnel network settings and not starting Psiphon tunnel.

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
                               json:@{@"StopReason": [PacketTunnelUtils textStopReason:reason],
                                      @"StopCode": @(reason)}];

    // Cleanup.
    [subscriptionDisposable dispose];
    
    [self.psiphonTunnel stop];
}

- (void)reconnectWithConfig:(NSString *_Nullable)sponsorId {
    dispatch_async(self->workQueue, ^{
        [AppProfiler logMemoryReportWithTag:@"reconnectWithConfig"];
        [self.psiphonTunnel reconnectWithConfig:sponsorId :[self getAllAuthorizations]];
    });
}

- (void)displayMessageAndKillExtension:(NSString *)message {

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
            exit(1);
        }];
    };

    if (self.tunnelProviderState == TunnelProviderStateKillMessageSent) {
        return;
    }

    self.tunnelProviderState = TunnelProviderStateKillMessageSent;

    displayAndKill(message);
}

#pragma mark - Query methods

- (BOOL)isNEZombie {
    return self.tunnelProviderState == TunnelProviderStateZombie;
}

- (BOOL)isTunnelConnected {
    return [self.psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected;
}

#pragma mark - Notifier callback

- (void)onMessageReceived:(NotifierMessage)message {

    if ([NotifierStartVPN isEqualToString:message]) {

        LOG_DEBUG(@"container signaled VPN to start");

        // If the tunnel is connected, starts the VPN.
        // Otherwise, should establish the VPN after onConnected has been called.
        self.shouldStartVPN = TRUE; // This should be set before calling tryStartVPN.
        [self tryStartVPN];

    } else if ([NotifierAppEnteredBackground isEqualToString:message]) {

        LOG_DEBUG(@"container entered background");

        // If the VPN start message ("M.startVPN") has not been received from the container,
        // and the container goes to the background, then alert the user to open the app.
        //
        // Note: We expect the value of shouldStartVPN to not be altered after it is set to TRUE.
        if (!self.shouldStartVPN) {
            [self displayMessage:NSLocalizedStringWithDefaultValue(@"OPEN_PSIPHON_APP", nil, [NSBundle mainBundle], @"Please open Psiphon app to finish connecting.", @"Alert message informing the user they should open the app to finish connecting to the VPN. DO NOT translate 'Psiphon'.")];
        }

    } else if ([NotifierForceSubscriptionCheck isEqualToString:message]) {

        // Container received a new subscription transaction.
        [PsiFeedbackLogger infoWithType:ExtensionNotificationLogType message:@"force subscription check"];
        [self scheduleSubscriptionCheckWithRemoteCheckForced:TRUE];

    } else if ([NotifierUpdatedAuthorizations isEqualToString:message]) {

        // Restarts the tunnel only if the persisted authorizations have changed from the
        // last set of authorizations supplied to tunnel-core.
        NSSet<NSString *> *nonMarkedAuths = [Authorization authorizationIDsFrom:[
          self.sharedDB getNonMarkedAuthorizations]];

        if (![nonMarkedAuths isEqualToSet:self.suppliedContainerAuthorizationIDs]) {
            [self reconnectWithConfig:nil];
        }

    }

}

#pragma mark -

- (void)sleepWithCompletionHandler:(void (^)(void))completionHandler {
    [self.psiphonTunnel setSleeping:TRUE];
    completionHandler();
}

- (void)wake {
    [self.psiphonTunnel setSleeping:FALSE];
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

// Starts VPN and notifies the container of homepages (if any) when shouldStartVPN flag is TRUE.
- (BOOL)tryStartVPN {
    // Don't start the VPN unless this flag has been due to subscription status, or from the container.
    if (!self.shouldStartVPN) {
        return FALSE;
    }

    if ([self.psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected) {
        // The container waits up to `kLandingPageTimeoutSecs` to see the tunnel connected
        // status from when the Homepage notification is received by it.
        self.reasserting = FALSE;
        [self startVPN];
        [[Notifier sharedInstance] post:NotifierNewHomepages];
        return TRUE;
    }

    return FALSE;
}

#pragma mark - Subscription and authorizations

// Returns possibly empty array of authorizations.
- (NSArray<NSString *> *_Nonnull)getAllAuthorizations {

    NSMutableArray *auths = [NSMutableArray arrayWithCapacity:1];
    
    // Add subscription authorization.
    Subscription *subscription = [Subscription fromPersistedDefaults];
    if (subscription.authorization) {
        [PsiFeedbackLogger infoWithType:PacketTunnelProviderLogType message:@"subscription authorization ID:%@", subscription.authorization.ID];
        [auths addObject:subscription.authorization.base64Representation];
    }
    
    // Adds authorizations persisted by the container (minus the authorizations already marked as expired).
    NSSet<Authorization *> *_Nonnull nonMarkedAuths = [self.sharedDB getNonMarkedAuthorizations];
    [auths addObjectsFromArray:[Authorization encodeAuthorizations:nonMarkedAuths]];
    
    self.suppliedContainerAuthorizationIDs = [Authorization authorizationIDsFrom:nonMarkedAuths];

    return auths;
}

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

    __weak PacketTunnelProvider *weakSelf = self;

    const int64_t intervalSec = 60; // Every minute.

    [self displayMessage:
        NSLocalizedStringWithDefaultValue(@"CANNOT_START_TUNNEL_DUE_TO_SUBSCRIPTION", nil, [NSBundle mainBundle], @"Your Psiphon subscription has expired.\nSince you're not a subscriber or your subscription has expired, Psiphon can only be started from the Psiphon app.\n\nPlease open the Psiphon app.", @"Alert message informing user that their subscription has expired or that they're not a subscriber, therefore Psiphon can only be started from the Psiphon app. DO NOT translate 'Psiphon'.")
       completionHandler:^(BOOL success) {
           // If the user dismisses the message, show the alert again in intervalSec seconds.
           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, intervalSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
               [weakSelf displayRepeatingZombieAlert];
           });
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
               [PsiFeedbackLogger error:@"iOS was unable to display subscription grace period starting message"];
               return;
           }

           dispatch_after(dispatch_walltime(NULL, gracePeriodSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
               weakSelf.gracePeriodState = GracePeriodStateDone;
               [self scheduleSubscriptionCheckWithRemoteCheckForced:FALSE];
           });
       }];
}

- (void)killExtensionForExpiredSubscription {
    NSString *message = NSLocalizedStringWithDefaultValue(@"TUNNEL_KILLED", nil, [NSBundle mainBundle], @"Psiphon has been stopped automatically since your subscription has expired.", @"Alert message informing user that Psiphon has been stopped automatically since the subscription has expired. Do not translate 'Psiphon'.");
    [self displayMessageAndKillExtension:message];
}

- (void)killExtensionForBadClock {
    [PsiFeedbackLogger errorWithType:ExitReasonLogType message:@"bad clock"];
    NSString *message = NSLocalizedStringWithDefaultValue(@"BAD_CLOCK_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"We've detected the time on your device is out of sync with your time zone. Please update your clock settings and restart the app", @"Alert message informing user that the device clock needs to be updated with current time");
    [self displayMessageAndKillExtension:message];
}

- (void)killExtensionForInvalidReceipt {
    [PsiFeedbackLogger errorWithType:ExitReasonLogType message:@"invalid subscription receipt"];
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
    return PsiphonConfigReader.embeddedServerEntriesPath;
}

- (NSDictionary * _Nullable)getPsiphonConfig {

    NSDictionary *configs = [PsiphonConfigReader fromConfigFile].configs;
    if (!configs) {
        [self displayCorruptSettingsFileMessage];
        abort();
    }

    // Get a mutable copy of the Psiphon configs.
    NSMutableDictionary *mutableConfigCopy = [configs mutableCopy];

    // Applying mutations to config
    NSNumber *fd = (NSNumber*)[[self packetFlow] valueForKeyPath:@"socket.fileDescriptor"];

    // In case of duplicate keys, value from psiphonConfigUserDefaults
    // will replace mutableConfigCopy value.
    PsiphonConfigUserDefaults *psiphonConfigUserDefaults = [[PsiphonConfigUserDefaults alloc]
      initWithSuiteName:APP_GROUP_IDENTIFIER];
    [mutableConfigCopy addEntriesFromDictionary:[psiphonConfigUserDefaults dictionaryRepresentation]];

    mutableConfigCopy[@"PacketTunnelTunFileDescriptor"] = fd;

    mutableConfigCopy[@"ClientVersion"] = [AppInfo appVersion];

    NSArray *authorizations = [self getAllAuthorizations];
    if ([authorizations count] > 0) {
        mutableConfigCopy[@"Authorizations"] = [authorizations copy];
    }

    // SponsorId override
    if ([self.subscriptionCheckState isSubscribed]) {
        mutableConfigCopy[@"SponsorId"] = [self.cachedSpondorIDs.subscriptionSponsorId copy];
    } else if ([self.subscriptionCheckState isInProgress]) {
        mutableConfigCopy[@"SponsorId"] = [self.cachedSpondorIDs.checkSubscriptionSponsorId copy];
    }

    // Store current sponsor ID used for use by container.
    [self.sharedDB setCurrentSponsorId:mutableConfigCopy[@"SponsorId"]];

    return mutableConfigCopy;
}

- (void)onConnectionStateChangedFrom:(PsiphonConnectionState)oldState to:(PsiphonConnectionState)newState {
    // Do not block PsiphonTunnel callback queue.
    // Note: ReactiveObjC subjects block until all subscribers have received to the events,
    //       and also ReactiveObjC `subscribeOn` operator does not behave similar to RxJava counterpart for example.
    dispatch_async_global(^{
        [self->tunnelConnectionStateSubject sendNext:@(newState)];
    });
}

- (void)onConnecting {
    self.reasserting = TRUE;
}

- (void)onStartedWaitingForNetworkConnectivity {
    [[Notifier sharedInstance] post:NotifierWaitingForNetworkConnectivity];
}

- (void)onActiveAuthorizationIDs:(NSArray * _Nonnull)authorizationIds {

    __weak PacketTunnelProvider *weakSelf = self;

    dispatch_async(self->workQueue, ^{

        if (!weakSelf) {
            return;
        }

        PacketTunnelProvider *strongSelf = weakSelf;

        // It is assumed that the subscription info at this point is the same as the subscription info
        // passed in getPsiphonConfig callback.
        Subscription *subscription = [Subscription fromPersistedDefaults];
        if (subscription.authorization && ![authorizationIds containsObject:subscription.authorization.ID]) {

            // Remove persisted authorization.
            subscription.authorization = nil;
            [subscription persistChanges];

            // Send value SubscriptionAuthorizationStatusRejected if subscription authorization was invalid.
            [strongSelf->subscriptionAuthorizationActiveSubject sendNext:@(SubscriptionAuthorizationStatusRejected)];

        } else {
            // Send value SubscriptionAuthorizationStatusActiveOrEmpty if subscription authorization was not invalid (i.e. authorization is non-existent or valid)
            [strongSelf->subscriptionAuthorizationActiveSubject sendNext:@(SubscriptionAuthorizationStatusActiveOrEmpty)];
        }

        // Marks container authorizations found to be invalid, and sends notification to the container.
        if ([self.suppliedContainerAuthorizationIDs count] > 0) {

            // Subtracts provided active authorizations from the the set of authorizations supplied in Psiphon config,
            // to get the set of inactive authorizations.
            NSMutableSet<NSString *> *inactiveAuthIDs = [NSMutableSet setWithSet:self.suppliedContainerAuthorizationIDs];
            [inactiveAuthIDs minusSet:[NSSet setWithArray:authorizationIds]];

            // Append inactive authorizations.
            [self.sharedDB appendExpiredAuthorizationIDs:inactiveAuthIDs];

            [[Notifier sharedInstance] post:NotifierMarkedAuthorizations];

        }

        if ([strongSelf.subscriptionCheckState isSubscribedOrInProgress]) {
            [strongSelf scheduleSubscriptionCheckWithRemoteCheckForced:FALSE];
        }
    });
}

- (void)onConnected {
    [AppProfiler logMemoryReportWithTag:@"onConnected"];
    LOG_DEBUG(@"connected with %@", [self.subscriptionCheckState textDescription]);
    [[Notifier sharedInstance] post:NotifierTunnelConnected];
    [self tryStartVPN];
}

- (void)onServerTimestamp:(NSString * _Nonnull)timestamp {

    dispatch_async(self->workQueue, ^{
        
        [self.sharedDB updateServerTimestamp:timestamp];

        NSDate *serverTimestamp = [NSDate fromRFC3339String:timestamp];

        // Check if user has an active subscription in the device's time
        // If NO - do nothing
        // If YES - proceed with checking the subscription against server timestamp
        Subscription *subscription = [Subscription fromPersistedDefaults];
        if ([subscription hasActiveAuthorizationForDate:[NSDate date]]) {
            if (serverTimestamp != nil) {
                if (![subscription hasActiveAuthorizationForDate:serverTimestamp]) {
                    // User is possibly cheating, terminate extension due to 'Bad Clock'.
                    [self killExtensionForBadClock];
                }
            }
        }
    });
}

- (void)onAvailableEgressRegions:(NSArray *)regions {
    [self.sharedDB insertNewEgressRegions:regions];

    [[Notifier sharedInstance] post:NotifierAvailableEgressRegions];

    PsiphonConfigUserDefaults *userDefaults = [PsiphonConfigUserDefaults sharedInstance];

    NSString *selectedRegion = [userDefaults egressRegion];
    if (selectedRegion && ![selectedRegion isEqualToString:kPsiphonRegionBestPerformance] && ![regions containsObject:selectedRegion]) {
        [[PsiphonConfigUserDefaults sharedInstance] setEgressRegion:kPsiphonRegionBestPerformance];

        [self displayMessageAndKillExtension:NSLocalizedStringWithDefaultValue(@"VPN_START_FAIL_REGION_INVALID_MESSAGE", nil, [NSBundle mainBundle], @"The region you selected is no longer available. You must choose a new region or change to the default \"Best performance\" choice.", @"Alert dialog message informing the user that an error occurred while starting Psiphon because they selected an egress region that is no longer available (Do not translate 'Psiphon'). The user should select a different region and try again. Note: the backslash before each quotation mark should be left as is for formatting.")];
    }
}

- (void)onInternetReachabilityChanged:(Reachability* _Nonnull)reachability {
    NSString *strReachabilityFlags = [reachability currentReachabilityFlagsToString];
    LOG_DEBUG(@"onInternetReachabilityChanged: %@", strReachabilityFlags);
}

- (NSString * _Nullable)getHomepageNoticesPath {
    return [self.sharedDB homepageNoticesPath];
}

- (NSString * _Nullable)getRotatingNoticesPath {
    return [self.sharedDB rotatingLogNoticesPath];
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
        NSLocalizedStringWithDefaultValue(@"CHECK_UPSTREAM_PROXY_SETTING", nil, [NSBundle mainBundle], @"You have configured Psiphon to use an upstream proxy.\nHowever, we seem to be unable to connect to a Psiphon server through that proxy.\nPlease fix the settings and try again.", @"Main text in the 'Upstream Proxy Error' dialog box. This is shown when the user has directly altered these settings, and those settings are (probably) erroneous. DO NOT translate 'Psiphon'."),
            message];

    [self displayMessage:alertDisplayMessage];
}

- (void)onClientRegion:(NSString *)region {
    [self.sharedDB insertNewClientRegion:region];
}

@end
