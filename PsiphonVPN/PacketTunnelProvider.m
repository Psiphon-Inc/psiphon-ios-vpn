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
#import "SubscriptionVerifierService.h"
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
#import <ReactiveObjC/RACSubject.h>
#import <ReactiveObjC/RACReplaySubject.h>

NSErrorDomain _Nonnull const PsiphonTunnelErrorDomain = @"PsiphonTunnelErrorDomain";

PsiFeedbackLogType const SubscriptionCheckLogType = @"SubscriptionCheck";
PsiFeedbackLogType const ExtensionNotificationLogType = @"ExtensionNotification";
PsiFeedbackLogType const PsiphonTunnelDelegateLogType = @"PsiphonTunnelDelegate";
PsiFeedbackLogType const PacketTunnelProviderLogType = @"PacketTunnelProvider";
PsiFeedbackLogType const ExitReasonLogType = @"ExitReason";

/** Status of subscription authorization included in Psiphon config. */
typedef NS_ENUM(NSInteger, SubscriptionAuthorizationStatus) {
    /** @const SubscriptionAuthorizationStatusRejected Authorization was rejected by Psiphon. */
    SubscriptionAuthorizationStatusRejected,
    /** @const SubscriptionAuthorizationStatusActiveOrEmpty Authorization was either accepted by Psiphon, or no authorization was sent. */
    SubscriptionAuthorizationStatusActiveOrEmpty
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

// waitForContainerStartVPNCommand signals that the extension should wait for the container
// before starting the VPN.
@property (atomic) BOOL waitForContainerStartVPNCommand;

@property (nonatomic, nonnull) PsiphonTunnel *psiphonTunnel;

// Authorization IDs supplied to tunnel-core from the container.
// NOTE: Does not include subscription authorization ID.
@property (atomic, nonnull) NSSet<NSString *> *suppliedContainerAuthorizationIDs;

@property (nonatomic) PsiphonConfigSponsorIds *cachedSponsorIDs;

// Notifier message state management.
@property (atomic) BOOL postedNetworkConnectivityFailed;

@end

@implementation PacketTunnelProvider {

    _Atomic BOOL showUpstreamProxyErrorMessage;

    // Serial queue of work to be done following callbacks from PsiphonTunnel.
    dispatch_queue_t workQueue;

    // Scheduler to be used by AppStore subscription check code.
    // NOTE: RACScheduler objects are all serial schedulers and cheap to create.
    //       The underlying implementation creates a GCD dispatch queues.
    RACScheduler *_Nullable subscriptionScheduler;

    // An infinite signal that emits Psiphon tunnel connection state.
    // When subscribed, replays the last known connection state.
    // @scheduler Events are delivered on some background system thread.
    RACReplaySubject<NSNumber *> *_Nullable tunnelConnectionStateSubject;

    // An infinite signal that emits @(SubscriptionAuthorizationStatusRejected) if the subscription authorization
    // was invalid, and @(SubscriptionAuthorizationStatusActiveOrEmpty) if it was valid (or non-existent).
    // When subscribed, replays the last item this subject was sent by onActiveAuthorizationIDs callback.
    RACReplaySubject<NSNumber *> *_Nullable subscriptionAuthorizationActiveSubject;

    RACDisposable *_Nullable subscriptionDisposable;

    AppProfiler *_Nullable appProfiler;
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
        _waitForContainerStartVPNCommand = FALSE;
        _suppliedContainerAuthorizationIDs = [NSSet set];

        _postedNetworkConnectivityFailed = FALSE;
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
        [PsiFeedbackLogger infoWithType:SubscriptionCheckLogType message:@"authorization expired restarting tunnel"];

        // Restarts the tunnel to re-connect with the correct sponsor ID.
        [weakSelf.subscriptionCheckState setStateNotSubscribed];
        [weakSelf reconnectWithConfig:weakSelf.cachedSponsorIDs.defaultSponsorId];
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
                        return [SubscriptionVerifierService localSubscriptionCheck];
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
      flattenMap:^RACSignal<SubscriptionResultModel *> *(NSNumber *subscriptionCheckObject) {

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
                  [weakSelf exitGracefully];
                  return [RACSignal empty];
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
                      [weakSelf exitForInvalidReceipt];
                      break;

                  case SubscriptionResultErrorExpired:
                      handleExpiredSubscription();
                      break;

                  default:
                      [PsiFeedbackLogger errorWithType:SubscriptionCheckLogType message:@"unhandled error code %ld", (long) result.error.code];
                      [weakSelf exitGracefully];
                      break;
              }
              return;
          }

          // At this point, subscription check finished and received response
          // from the subscription verifier server.

          @autoreleasepool {

              NSString *currentActiveAuthorization;

              // Updates subscription and persists subscription.
              MutableSubscriptionData *subscription = [MutableSubscriptionData fromPersistedDefaults];

              // Keep a copy of the authorization passed to the tunnel previously.
              // This represents the authorization accepted by the Psiphon server,
              // regardless of what authorization was passed to the server.
              currentActiveAuthorization = [subscription.authorization.ID copy];

              [subscription updateWithRemoteAuthDict:result.remoteAuthDict submittedReceiptFilesize:result.submittedReceiptFileSize];

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
                      [self exitForBadClock];
                      return;
                  }
              }

              if (subscription.authorization) {
                  // New authorization was received from the subscription verifier server.
                  // Restarts the tunnel to connect with the new authorization only if it is different from
                  // the authorization in use by the tunnel.
                  if (![subscription.authorization.ID isEqualToString:currentActiveAuthorization]) {
                      [weakSelf.subscriptionCheckState setStateSubscribed];
                      [weakSelf reconnectWithConfig:weakSelf.cachedSponsorIDs.subscriptionSponsorId];
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
- (void)startTunnelWithErrorHandler:(void (^_Nonnull)(NSError *_Nonnull error))errorHandler {

    __weak PacketTunnelProvider *weakSelf = self;

    // In prod starts app profiling.
    [self updateAppProfiling];

    [[Notifier sharedInstance] registerObserver:self callbackQueue:dispatch_get_main_queue()];

    self.cachedSponsorIDs = [PsiphonConfigReader fromConfigFile].sponsorIds;

    // Initializes uninitialized properties.
    MutableSubscriptionData *subscription = [MutableSubscriptionData fromPersistedDefaults];
    self.subscriptionCheckState = [SubscriptionState initialStateFromSubscription:subscription];

    [PsiFeedbackLogger infoWithType:PacketTunnelProviderLogType
                               json:@{@"Event":@"Start",
                                      @"StartMethod": [self extensionStartMethodTextDescription],
                                      @"SubscriptionState": [self.subscriptionCheckState textDescription]}];

    if (self.extensionStartMethod == ExtensionStartMethodFromContainer
        || self.extensionStartMethod == ExtensionStartMethodFromCrash
        || [self.subscriptionCheckState isSubscribedOrInProgress]) {

        if (![self.subscriptionCheckState isSubscribedOrInProgress] &&
            self.extensionStartMethod == ExtensionStartMethodFromContainer) {
            self.waitForContainerStartVPNCommand = TRUE;
        }

        if ([self.subscriptionCheckState isSubscribedOrInProgress]) {
            [self initSubscriptionCheckObjects];
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
    return @(self.tunnelProviderState == TunnelProviderStateZombie);
}

- (NSNumber *)isTunnelConnected {
    return @([self.psiphonTunnel getConnectionState] == PsiphonConnectionStateConnected);
}

- (NSNumber *)isNetworkReachable {
    NetworkStatus status;
    if ([self.psiphonTunnel getNetworkReachabilityStatus:&status]) {
        return @(status != NotReachable);
    }
    return nil;
}

#pragma mark - Notifier callback

- (void)onMessageReceived:(NotifierMessage)message {

    if ([NotifierStartVPN isEqualToString:message]) {

        LOG_DEBUG(@"container signaled VPN to start");

        self.waitForContainerStartVPNCommand = FALSE;
        [self tryStartVPN];

    } else if ([NotifierAppEnteredBackground isEqualToString:message]) {

        LOG_DEBUG(@"container entered background");

        // If the container StartVPN command has not been received from the container,
        // and the container goes to the background, then alert the user to open the app.
        if (self.waitForContainerStartVPNCommand) {
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
        // The container waits up to `LandingPageTimeout` to see the tunnel connected
        // status from when the Homepage notification is received by it.
        [self startVPN];
        self.reasserting = FALSE;
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
    SubscriptionData *subscription = [SubscriptionData fromPersistedDefaults];
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
        NSLocalizedStringWithDefaultValue(@"CANNOT_START_TUNNEL_DUE_TO_SUBSCRIPTION", nil, [NSBundle mainBundle], @"You don't have an active subscription.\nSince you're not a subscriber or your subscription has expired, Psiphon can only be started from the Psiphon app.\n\nPlease open the Psiphon app to start.", @"Alert message informing user that their subscription has expired or that they're not a subscriber, therefore Psiphon can only be started from the Psiphon app. DO NOT translate 'Psiphon'.")
       completionHandler:^(BOOL success) {
           // If the user dismisses the message, show the alert again in intervalSec seconds.
           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, intervalSec * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
               [weakSelf displayRepeatingZombieAlert];
           });
       }];
}

- (void)exitForBadClock {
    [PsiFeedbackLogger errorWithType:ExitReasonLogType message:@"bad clock"];
    NSString *message = NSLocalizedStringWithDefaultValue(@"BAD_CLOCK_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"We've detected the time on your device is out of sync with your time zone. Please update your clock settings and restart the app", @"Alert message informing user that the device clock needs to be updated with current time");
    [self displayMessageAndExitGracefully:message];
}

- (void)exitForInvalidReceipt {
    [PsiFeedbackLogger errorWithType:ExitReasonLogType message:@"invalid subscription receipt"];
    NSString *message = NSLocalizedStringWithDefaultValue(@"BAD_RECEIPT_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"Your subscription receipt can not be verified, please refresh it and try again.", @"Alert message informing user that subscription receipt can not be verified");
    [self displayMessageAndExitGracefully:message];
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
        [PsiFeedbackLogger errorWithType:PsiphonTunnelDelegateLogType
                                 message:@"Failed to get config"];
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
                                 message:@"Failed to get data root directory"];
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
                                message:@"Failed to get old rotating notices log path"];
    }

    NSString *oldHomepageNoticesPath = [self.sharedDB oldHomepageNoticesPath];
    if (oldHomepageNoticesPath) {
        mutableConfigCopy[@"MigrateHompageNoticesFilename"] = oldHomepageNoticesPath;
    } else {
        [PsiFeedbackLogger infoWithType:PsiphonTunnelDelegateLogType
                                message:@"Failed to get old homepage notices path"];
    }

    // Use default rotation rules for homepage and notice files.
    // Note: homepage and notice files are only used if this field is set.
    NSMutableDictionary *noticeFiles = [[NSMutableDictionary alloc] init];
    [noticeFiles setObject:@0 forKey:@"RotatingFileSize"];
    [noticeFiles setObject:@0 forKey:@"RotatingSyncFrequency"];

    mutableConfigCopy[@"UseNoticeFiles"] = noticeFiles;

    // Provide auth tokens
    NSArray *authorizations = [self getAllAuthorizations];
    if ([authorizations count] > 0) {
        mutableConfigCopy[@"Authorizations"] = [authorizations copy];
    }

    // SponsorId override
    if ([self.subscriptionCheckState isSubscribed]) {
        mutableConfigCopy[@"SponsorId"] = [self.cachedSponsorIDs.subscriptionSponsorId copy];
    } else if ([self.subscriptionCheckState isInProgress]) {
        mutableConfigCopy[@"SponsorId"] = [self.cachedSponsorIDs.checkSubscriptionSponsorId copy];
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

    dispatch_async_global(^{
        PacketTunnelProvider *__strong strongSelf = self;
        if (strongSelf) {
            [strongSelf->tunnelConnectionStateSubject sendNext:@(newState)];
        }
    });

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

    __weak PacketTunnelProvider *weakSelf = self;

    dispatch_async(self->workQueue, ^{

        if (!weakSelf) {
            return;
        }

        PacketTunnelProvider *strongSelf = weakSelf;

        // It is assumed that the subscription info at this point is the same as the subscription info
        // passed in getPsiphonConfig callback.
        SubscriptionData *subscription = [SubscriptionData fromPersistedDefaults];
        if (subscription.authorization && ![authorizationIds containsObject:subscription.authorization.ID]) {

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
        SubscriptionData *subscription = [SubscriptionData fromPersistedDefaults];
        if ([subscription hasActiveAuthorizationForDate:[NSDate date]]) {
            if (serverTimestamp != nil) {
                if (![subscription hasActiveAuthorizationForDate:serverTimestamp]) {
                    // User is possibly cheating, terminate extension due to 'Bad Clock'.
                    [self exitForBadClock];
                }
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
        NSLocalizedStringWithDefaultValue(@"CHECK_UPSTREAM_PROXY_SETTING", nil, [NSBundle mainBundle], @"You have configured Psiphon to use an upstream proxy.\nHowever, we seem to be unable to connect to a Psiphon server through that proxy.\nPlease fix the settings and try again.", @"Main text in the 'Upstream Proxy Error' dialog box. This is shown when the user has directly altered these settings, and those settings are (probably) erroneous. DO NOT translate 'Psiphon'."),
            message];

    [self displayMessage:alertDisplayMessage];
}

- (void)onClientRegion:(NSString *)region {
    [self.sharedDB insertNewClientRegion:region];
}

@end
