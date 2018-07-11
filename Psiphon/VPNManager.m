/*
 * Copyright (c) 2018, Psiphon Inc.
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

/**
 * Note on using `unsafeSubscribeOnSerialQueue` method of RACSignal+Operations2:
 *
 * - To avoid possible corruptions of the VPN configuration, the operations performed on the configurations
 *   should be performed serially. (That is the sequence of sub-operations in two different larger operations
 *   performed on the VPN configuration shouldn't interleave.)
 *
 *   `unsafeSubscribeOnSerialQueue` allows us to do that, with the caveat that when this signal is subscribed to,
 *   no other signal that's also subscribed on with `unsafeSubscribeOnSerialQueue` should be subscribed to.
 *
 */

#import <ReactiveObjC/RACScheduler.h>
#import <ReactiveObjC/RACTuple.h>
#import "VPNManager.h"
#import "AppInfo.h"
#import "AsyncOperation.h"
#import "Asserts.h"
#import "Notifier.h"
#import "SharedConstants.h"
#import "NSError+Convenience.h"
#import "RACSignal.h"
#import "RACReplaySubject.h"
#import "RACSequence.h"
#import "RACSignal+Operations2.h"
#import "SettingsViewController.h"
#import "NEBridge.h"
#import "AppDelegate.h"
#import "Logging.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACSignal+Operations.h"
#import "RACUnit.h"
#import "RACQueueScheduler+Subclass.h"
#import "DispatchUtils.h"
#import "RACTargetQueueScheduler.h"
#import "UnionSerialQueue.h"

NSErrorDomain const VPNManagerErrorDomain = @"VPNManagerErrorDomain";

PsiFeedbackLogType const VPNManagerLogType = @"VPNManager";

UserDefaultsKey const VPNManagerConnectOnDemandUntilNextStartBoolKey = @"VPNManager.ConnectOnDemandUntilNextStartKey";

@interface VPNManager ()

// Public properties
@property (nonatomic, readwrite) RACSignal<NSNumber *> *vpnStartStatus;

// Events should only be submitted to this subject on the main thread.
@property (nonatomic, readwrite) RACSignal<NSNumber *> *lastTunnelStatus;

@property (nonatomic, getter=tunnelProviderStatus) NEVPNStatus tunnelProviderStatus;

// Private properties
@property (getter=tunnelProviderManager, setter=setTunnelProviderManager:) NETunnelProviderManager *tunnelProviderManager;

@property (nonatomic) UnionSerialQueue *serialQueue;

@property (atomic) BOOL restartRequired;
@property (atomic) BOOL extensionIsZombie;

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

// Replay subjects are wrapped in signals that deliver only on the main thread.
@property (nonatomic) RACReplaySubject<NSNumber *> *internalStartStatus;

@property (nonatomic) RACReplaySubject *internalTunnelStatus;

@end

@implementation VPNManager {
    id localVPNStatusObserver;
}

@synthesize tunnelProviderManager = _tunnelProviderManager;

- (instancetype)init {
    self = [super init];
    if (self) {
        localVPNStatusObserver = nil;

        _internalStartStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _internalTunnelStatus = [RACReplaySubject replaySubjectWithCapacity:1];

        // Bootstrap connectionStatus with NEVPNStatusInvalid, until the actual status is determined.
        [_internalTunnelStatus sendNext:@(NEVPNStatusInvalid)];

        _restartRequired = FALSE;

        _restartRequired = FALSE;
        _extensionIsZombie = FALSE;

        _serialQueue = [UnionSerialQueue createWithLabel:@"ca.psiphon.Psiphon.VPNManagerSerialQueue"];

        // Public properties.
        __weak VPNManager *weakSelf = self;

        _vpnStartStatus = [_internalStartStatus deliverOnMainThread];

        _lastTunnelStatus = [[[_internalTunnelStatus
          filter:^BOOL(id value) {
              // RACUnit.defaultUnit is used as a special value indicating that last tunnel status
              // may no longer be valid.
              return (value != RACUnit.defaultUnit);
          }]
          map:^NSNumber *(NSNumber *connectionStatus) {
              NEVPNStatus s = (NEVPNStatus) [connectionStatus integerValue];
              return @([weakSelf mapVPNStatus:s]);
          }]
          deliverOnMainThread];

        _compoundDisposable = [RACCompoundDisposable compoundDisposable];

        // Listen to applicationDidEnterBackground notification.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onApplicationDidEnterBackground)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onApplicationWillEnterForeground)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];

    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:localVPNStatusObserver];
    [self.compoundDisposable dispose];
}

// when subscribed to, emits nullable `tunnelProviderManager`.
- (RACSignal<NETunnelProviderManager *> *)deferredTunnelProviderManager {
    __weak VPNManager *weakSelf = self;

    return [RACSignal defer:^RACSignal * {
        return [RACSignal return:weakSelf.tunnelProviderManager];
    }];
}

- (NEVPNStatus)tunnelProviderStatus {
    @synchronized (self) {
        if (self.tunnelProviderManager) {
            return self.tunnelProviderManager.connection.status;
        }

        return NEVPNStatusInvalid;
    }
}

// All operations involving `tunnelProviderManager` property are serialized on the `serialOperationQueue`.
// Prefer to use `deferredTunnelProviderManager` and use `unsafeSubscribeOnSerialQueue` to subscribe to the
// signal on the `serialOperationQueue` instead of using this getter.
- (NETunnelProviderManager *)tunnelProviderManager {
    @synchronized (self) {
        return _tunnelProviderManager;
    }
}

- (void)setTunnelProviderManager:(NETunnelProviderManager *)tunnelProviderManager {
    @synchronized (self) {
        _tunnelProviderManager = tunnelProviderManager;
        if (localVPNStatusObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:localVPNStatusObserver];
        }

        if (!_tunnelProviderManager) {
            [self.internalTunnelStatus sendNext:@(NEVPNStatusInvalid)];
            return;
        }

        [self.internalTunnelStatus sendNext:@(_tunnelProviderManager.connection.status)];

        __weak VPNManager *weakSelf = self;

        // Listening to NEVPNManager status change notifications on the main thread.
        localVPNStatusObserver = [[NSNotificationCenter defaultCenter]
          addObserverForName:NEVPNStatusDidChangeNotification
                      object:_tunnelProviderManager.connection
                       queue:NSOperationQueue.mainQueue
                  usingBlock:^(NSNotification *_Nonnull note) {

                      // Observers of VPNManagerStatusDidChangeNotification will be notified at the same time.

                      [self.internalTunnelStatus sendNext:@(_tunnelProviderManager.connection.status)];

                      // If restartRequired flag is on, waits until VPN status is NEVPNStatusDisconnected.
                      if (_tunnelProviderManager.connection.status == NEVPNStatusDisconnected &&
                          weakSelf.restartRequired) {

                          // Schedule the tunnel to be restarted.
                          [weakSelf.serialQueue.operationQueue addOperationWithBlock:^{
                              weakSelf.restartRequired = FALSE;
                              [weakSelf startTunnel];
                          }];
                      }
                  }];
    }
}

#pragma mark - Public methods

+ (VPNManager *)sharedInstance {

    static dispatch_once_t once;
    static VPNManager *instance;

    dispatch_once(&once, ^{
        instance = [[VPNManager alloc] init];

        __weak VPNManager *weakInstance = instance;

        // Adds loading VPN operation to `serialOperationQueue` before returning shared instance.
        __block RACDisposable *disposable = [[[VPNManager loadTunnelProviderManager]
          unsafeSubscribeOnSerialQueue:instance.serialQueue
                              withName:@"initOperation"]
          subscribeNext:^(NETunnelProviderManager *tunnelProvider) {
              if (tunnelProvider) {
                  instance.tunnelProviderManager = tunnelProvider;
              }
          }
          error:^(NSError *error) {
              [PsiFeedbackLogger errorWithType:VPNManagerLogType message:@"failed to load initial VPN config" object:error];
              [weakInstance.compoundDisposable removeDisposable:disposable];
          }
          completed:^{
              [weakInstance.compoundDisposable removeDisposable:disposable];
          }];

        [instance.compoundDisposable addDisposable:disposable];
    });
    return instance;
}

+ (NSString *)statusText:(NSInteger)status {
    switch (status) {

        case VPNStatusInvalid: return @"invalid";
        case VPNStatusDisconnected: return @"disconnected";
        case VPNStatusConnecting: return @"connecting";
        case VPNStatusConnected: return @"connected";
        case VPNStatusReasserting: return @"reasserting";
        case VPNStatusDisconnecting: return @"disconnecting";
        case VPNStatusRestarting: return @"restarting";
        case VPNStatusZombie: return @"zombie";

        default: return [NSString stringWithFormat:@"invalid status (%ld)", (long)status];
    }
}

+ (NSString *)statusTextSystem:(NEVPNStatus)status {
    switch (status) {

        case NEVPNStatusInvalid: return @"invalid";
        case NEVPNStatusDisconnected: return @"disconnected";
        case NEVPNStatusConnecting: return @"connecting";
        case NEVPNStatusConnected: return @"connected";
        case NEVPNStatusReasserting: return @"reasserting";
        case NEVPNStatusDisconnecting: return @"disconnecting";

        default: return [NSString stringWithFormat:@"invalid status (%ld)", (long)status];
    }
}

// fix as in fix the zombie state
- (void)checkOrFixVPNStatus {

    __weak VPNManager *weakSelf = self;

    __block RACDisposable *disposable = [[[self isExtensionZombie]
      flattenMap:^RACSignal<NSNumber *> *(NSNumber *isZombie) {

          if ([isZombie boolValue]) {
              weakSelf.extensionIsZombie = TRUE;
              return [weakSelf setConnectOnDemandEnabled:FALSE];
          } else {
              return [RACSignal empty];
          }
      }]
      subscribeNext:^(NSNumber *x) {
          // Whether or not VPN configuration update succeeded or not, stop the VPN.
          [weakSelf stopVPN];
      }
      error:^(NSError *error) {
          [PsiFeedbackLogger errorWithType:VPNManagerLogType message:@"error killing zombie extension" object:error];
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }
      completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

- (void)startTunnel {

    // Sends VPNStartStatusStart eagerly, since the signal is subscribed on the `serialOperationQueue`
    // and would only be updated at some indeterminate time in the future.
    [self.internalStartStatus sendNext:@(VPNStartStatusStart)];

    __weak VPNManager *weakSelf = self;

    __block RACDisposable *disposable = [[[[[VPNManager loadTunnelProviderManager]
      flattenMap:^RACSignal *(NETunnelProviderManager *_Nullable providerManager) {
          // Updates VPN configuration parameters if it already exists,
          // otherwise creates a new VPN configuration.
          return [weakSelf updateOrCreateVPNConfigurationAndSave:providerManager];
      }]
      flattenMap:^RACSignal<NSNumber *> *(NETunnelProviderManager *providerManager) {

          NSError *error;
          NSDictionary *options = @{EXTENSION_OPTION_START_FROM_CONTAINER: EXTENSION_OPTION_TRUE};
          [weakSelf.tunnelProviderManager.connection startVPNTunnelWithOptions:options andReturnError:&error];

          if (error) {
              return [RACSignal error:error];
          } else {
              return [RACSignal return:RACUnit.defaultUnit];
          }

      }]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:@"startTunnelOperation"]
      subscribeError:^(NSError *error) {
          [PsiFeedbackLogger errorWithType:VPNManagerLogType message:@"failed to start" object:error];

          if ([error.domain isEqualToString:NEVPNErrorDomain] &&
               error.code == NEVPNErrorConfigurationReadWriteFailed &&
               [error.localizedDescription isEqualToString:@"permission denied"] ) {

              [weakSelf.internalStartStatus sendNext:@(VPNStartStatusFailedUserPermissionDenied)];
          } else {
              [weakSelf.internalStartStatus sendNext:@(VPNStartStatusFailedOther)];
          }

          [weakSelf.compoundDisposable removeDisposable:disposable];

      } completed:^{
          [weakSelf.internalStartStatus sendNext:@(VPNStartStatusFinished)];
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

- (void)startVPN {

    __weak VPNManager *weakSelf = self;

    __block RACDisposable *disposable = [[[self deferredTunnelProviderManager]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:@"startVPNOperation"]
      subscribeNext:^(NETunnelProviderManager *_Nullable providerManager) {

          if (!providerManager) {
              return;
          }

          if (providerManager.connection.status == NEVPNStatusConnecting) {
              [[Notifier sharedInstance] post:NotifierStartVPN];
          }

      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

- (void)stopVPN {

    __weak VPNManager *weakSelf = self;

    __block RACDisposable *disposable = [[[self deferredTunnelProviderManager]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:@"stopVPNOperation"]
      subscribeNext:^(NETunnelProviderManager *_Nullable providerManager) {

          [providerManager.connection stopVPNTunnel];

          // Tunnel is being stopped, and previous zombie status can be reset.
          weakSelf.extensionIsZombie = FALSE;

      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

- (void)restartVPNIfActive {

    __weak VPNManager *weakSelf = self;

    __block RACDisposable *disposable = [[[self deferredTunnelProviderManager]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:@"restartVPNIfActiveOperation"]
      subscribeNext:^(NETunnelProviderManager *_Nullable providerManager) {
          if (!providerManager) {
              return;
          }

          BOOL isActive = [VPNManager mapIsVPNActive:[weakSelf mapVPNStatus:providerManager.connection.status]];

          if (isActive) {
              weakSelf.restartRequired = TRUE;
              [providerManager.connection stopVPNTunnel];
          }

      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

// Removes and re-installs the VPN configuration.
// TODO: signal the state of the operation to the UI world.
- (void)reinstallVPNConfiguration {

    __weak VPNManager *weakSelf = self;

    __block RACDisposable *disposable = [[[[[VPNManager loadTunnelProviderManager]
      flattenMap:^RACSignal *(NETunnelProviderManager *providerManager) {
          // Removes the VPN configuration (if already installed).
          if (providerManager) {
              return [RACSignal defer:providerManager selectorWithErrorCallback:@selector(removeFromPreferencesWithCompletionHandler:)];
          }
          return [RACSignal return:nil];
      }]
      flattenMap:^RACSignal *(id x) {
          // Installs the VPN configuration.
          return [weakSelf updateOrCreateVPNConfigurationAndSave:nil];
      }]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:@"reinstallVPNConfigurationOperation"]
      subscribeError:^(NSError *error) {
          [PsiFeedbackLogger errorWithType:VPNManagerLogType message:@"failed to reinstall VPN configuration" object:error];
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

// isVPNActive returns a signal that when subscribed to emits tuple (isActive, VPNStatus).
// If tunnelProviderManager is nil emits (FALSE, VPNStatusInvalid)
- (RACSignal<RACTwoTuple<NSNumber *, NSNumber *> *> *)isVPNActive {

    __weak VPNManager *weakSelf = self;

    return [[self isExtensionZombie]
      flattenMap:^RACSignal *(NSNumber *_Nullable isZombie) {
          if ([isZombie boolValue]) {
              weakSelf.extensionIsZombie = TRUE;
              return [RACSignal return:[RACTwoTuple pack:[NSNumber numberWithBool:FALSE] :@(VPNStatusZombie)]];
          } else {
              return [[self deferredTunnelProviderManager]
                map:^RACTwoTuple<NSNumber *, NSNumber *> *(NETunnelProviderManager *_Nullable providerManager) {
                    if (providerManager) {
                        VPNStatus s = [weakSelf mapVPNStatus:(NEVPNStatus) providerManager.connection.status];
                        BOOL isActive = [VPNManager mapIsVPNActive:s];
                        return [RACTwoTuple pack:[NSNumber numberWithBool:isActive] :@(s)];
                    } else {
                        return [RACTwoTuple pack:[NSNumber numberWithBool:FALSE] :@(VPNStatusInvalid)];
                    }
                }];
          }
      }];
}

// isConnectOnDemandEnabled returns a signal that when subscribed to emits boolean value as NSNumber,
// if tunnelProviderManager is nil emits false.
- (RACSignal<NSNumber *> *)isConnectOnDemandEnabled {

    return [[[self deferredTunnelProviderManager]
      map:^NSNumber *(NETunnelProviderManager *_Nullable providerManager) {
          if (providerManager) {
              return [NSNumber numberWithBool:providerManager.isOnDemandEnabled];
          } else {
              return [NSNumber numberWithBool:FALSE];
          }
      }]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:@"isConnectOnDemandEnabled"];
}

// setConnectOnDemandEnabled: returns a signal that when subscribed to updates tunnelProviderManager's
// onDemandEnabled property with the provided parameter if different and then emits TRUE as NSNumber on success
// and FALSE on failure. If provided parameter is not different, then the returned signal
// emits TRUE and completes immediately.
// All errors are caught and logged, and FALSE is emitted in their place.
//
// If tunnelProviderManager is nil, returned signal completes immediately.
//
- (RACSignal<NSNumber *> *)setConnectOnDemandEnabled:(BOOL)onDemandEnabled {
    __weak VPNManager *weakSelf = self;

    return [[[[VPNManager loadTunnelProviderManager]
      flattenMap:^RACSignal<NETunnelProviderManager *> *(NETunnelProviderManager *providerManager) {

          if (!providerManager) {
              return [RACSignal empty];
          }

          // return empty signal as NO-OP if there is not change in status.
          if (providerManager.onDemandEnabled == onDemandEnabled) {
              return [RACSignal return:[NSNumber numberWithBool:TRUE]];
          }

          providerManager.onDemandEnabled = onDemandEnabled;

          if (onDemandEnabled) {
              // Auto-start VPN on demand has been turned on by the user.
              // To avoid unexpected conflict with other VPN configurations,
              // re-enable Psiphon's VPN configuration.
              providerManager.enabled = TRUE;
          }

          // Returned signal, saves and loads the tunnel provider manager.
          return [[[[RACSignal defer:providerManager selectorWithErrorCallback:@selector(saveToPreferencesWithCompletionHandler:)]
            flattenMap:^RACSignal<NETunnelProviderManager *> *(NETunnelProviderManager *manager) {
                return [RACSignal defer:manager selectorWithErrorCallback:@selector(loadFromPreferencesWithCompletionHandler:)];
            }]
            doNext:^(NETunnelProviderManager *manager) {
                weakSelf.tunnelProviderManager = manager;
            }]
            map:^NSNumber *(NETunnelProviderManager *x) {
                return [NSNumber numberWithBool:TRUE];
          }];

      }]
      catch:^RACSignal *(NSError *error) {
          [PsiFeedbackLogger errorWithType:VPNManagerLogType message:@"error setting OnDemandEnabled" object:error];
          return [RACSignal return:[NSNumber numberWithBool:FALSE]];
      }]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:@"setConnectOnDemandEnabledOperation"];
}

+ (BOOL)mapIsVPNActive:(VPNStatus)s {
    return (s == VPNStatusConnecting ||
            s == VPNStatusConnected ||
            s == VPNStatusReasserting ||
            s == VPNStatusRestarting );
}

#pragma mark - System event callbacks

- (void)onApplicationDidEnterBackground {

    // Resets states to a default value if they're state would be potentially invalid
    // after the app enters the background.

    [self.internalTunnelStatus sendNext:RACUnit.defaultUnit];
}

- (void)onApplicationWillEnterForeground {

    __weak VPNManager *weakSelf = self;

    __block RACDisposable *disposable = [[self deferredTunnelProviderManager]
      subscribeNext:^(NETunnelProviderManager *_Nullable tunnelProvider) {

        if (tunnelProvider.connection) {
            [weakSelf.internalTunnelStatus sendNext:@(tunnelProvider.connection.status)];
        }

      }
      error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }
      completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

#pragma mark - Private methods

- (VPNStatus)mapVPNStatus:(NEVPNStatus)status {

#if DEBUG
    if ([AppInfo runningUITest]) {
        return VPNStatusConnected;
    }
#endif

    if (self.restartRequired) {
        // If extension is restarting due to a call to restartVPNIfActive, then
        // we don't want to show the Disconnecting and Disconnected states
        // to the observers, and instead simply notify them that the
        // extension is restarting.
        return VPNStatusRestarting;
    }

    if (self.extensionIsZombie) {
        return VPNStatusZombie;
    }

    switch (status) {
        case NEVPNStatusInvalid: return VPNStatusInvalid;
        case NEVPNStatusDisconnected: return VPNStatusDisconnected;
        case NEVPNStatusConnecting: return VPNStatusConnecting;
        case NEVPNStatusConnected: return VPNStatusConnected;
        case NEVPNStatusReasserting: return VPNStatusReasserting;
        case NEVPNStatusDisconnecting: return VPNStatusDisconnecting;
    }

    [PsiFeedbackLogger error:@"Unknown NEVPNConnection status: (%ld)", (long) status];
    return VPNStatusInvalid;
}

// loadTunnelProviderManager returns a signal that when subscribed to emits an instance of NETunnelProviderManager
// if one was previously saved in the Network Extension preferences.
// Emits nil if no VPN configuration was previously saved, or if more than 1 VPN configuration was saved.
//
// Note: In case of more than 1 VPN configuration, all loaded VPN configurations are removed
// from Network Extension Preferences before nil is emitted to the observer.
//
+ (RACSignal<NETunnelProviderManager *> *)loadTunnelProviderManager {

    RACSignal<NSArray<NETunnelProviderManager *> *> *loadAllConfigurationsSignal = [RACSignal
      createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

          [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:
            ^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {

                if (error) {
                    [subscriber sendError:error];
                } else {
                    [subscriber sendNext:managers];
                    [subscriber sendCompleted];
                }

          }];

          return nil;
    }];

    return [loadAllConfigurationsSignal
      flattenMap:^RACSignal *(NSArray<NETunnelProviderManager *> *managers) {

          if ([managers count] == 0) {
              return [RACSignal return:nil];
          } else if ([managers count] == 1) {
              return [RACSignal return:managers[0]];
          } else {
              // Remove all VPN configurations.
              return [[[[RACSignal fromArray:managers]
                flattenMap:^RACSignal *(NETunnelProviderManager *providerManager) {
                    return [RACSignal defer:providerManager
                  selectorWithErrorCallback:@selector(removeFromPreferencesWithCompletionHandler:)];
                }]
                collect]
                map:^id(NSArray *value) {
                    // Don't emit NSArray of deleted VPN configurations, just return nil.
                  return nil;
              }];
          }
      }];
}

// Returns a signal that when subscribed to, creates and saves VPN configuration if nil is passed.
// Otherwise, updates appropriate properties in the provided VPN configuration and saves it.
// NOTE: since this signal modifies the VPN configuration, the returned signal should be subscribed on using
//       `unsafeSubscribeOnSerialQueue`.
- (RACSignal<NETunnelProviderManager *> *)updateOrCreateVPNConfigurationAndSave:
  (NETunnelProviderManager *_Nullable)manager {

    __weak VPNManager *weakSelf = self;

    // Emits a single item of type UserSubscriptionStatus whenever the subscription status is known.
    RACSignal *knownSubStatus = [[AppDelegate.sharedAppDelegate.subscriptionStatus
      filter:^BOOL(NSNumber *value) {
          UserSubscriptionStatus s = (UserSubscriptionStatus) [value integerValue];
          return (s != UserSubscriptionUnknown);
      }]
      take:1];

    return [[[[[[RACSignal return:manager] zipWith:knownSubStatus]
      map:^NETunnelProviderManager *(RACTwoTuple *tuple) {

          NETunnelProviderManager *providerManager = tuple.first;
          UserSubscriptionStatus subscriptionStatus = (UserSubscriptionStatus)[tuple.second integerValue];

          if (!providerManager) {
              NETunnelProviderProtocol *providerProtocol = [[NETunnelProviderProtocol alloc] init];
              providerProtocol.providerBundleIdentifier = @"ca.psiphon.Psiphon.PsiphonVPN";
              providerProtocol.serverAddress = @"localhost";

              providerManager = [[NETunnelProviderManager alloc] init];
              providerManager.protocolConfiguration = providerProtocol;
          }

          // setEnabled becomes false if the user changes the
          // enabled VPN Configuration from the preferences.
          providerManager.enabled = TRUE;

          // Adds "always connect" Connect On Demand rule to the configuration.
          if (!providerManager.onDemandRules || [providerManager.onDemandRules count] == 0) {
              NEOnDemandRule *alwaysConnectRule = [NEOnDemandRuleConnect new];
              providerManager.onDemandRules = @[alwaysConnectRule];
          }

          // Enables Connect On Demand if the user has an active subscription.
          if (subscriptionStatus == UserSubscriptionActive) {
              providerManager.onDemandEnabled = TRUE;
          }

          NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
          if ([ud boolForKey:VPNManagerConnectOnDemandUntilNextStartBoolKey]) {
              providerManager.onDemandEnabled = TRUE;

              // Reset VPNManagerConnectOnDemandUntilNextStartBoolKey value.
              [ud setBool:FALSE forKey:VPNManagerConnectOnDemandUntilNextStartBoolKey];
          }

          return providerManager;
      }]
      flattenMap:^RACSignal *(NETunnelProviderManager *providerManager) {
          return [RACSignal defer:providerManager selectorWithErrorCallback:@selector(saveToPreferencesWithCompletionHandler:)];
      }]
      flattenMap:^RACSignal *(NETunnelProviderManager *providerManager) {
          return [RACSignal defer:providerManager selectorWithErrorCallback:@selector(loadFromPreferencesWithCompletionHandler:)];
      }]
      map:^id(NETunnelProviderManager *providerManager) {
          weakSelf.tunnelProviderManager = providerManager;
          return providerManager;
      }];
}

#pragma mark - Extension Query

// isPsiphonTunnelConnected returns a signal that when subscribed to sends "isProviderZombie" query to the extension
// and then emits boolean response as NSNumber, or the signal completes immediately if extension is not active.
// Note: the returned signal emits FALSE if the extension returns empty response.
- (RACSignal<NSNumber *> *)isExtensionZombie {
    return [[self queryActiveVPN:EXTENSION_QUERY_IS_PROVIDER_ZOMBIE]
      catch:^RACSignal<NSNumber *> *(NSError *error) {
          [PsiFeedbackLogger warnWithType:VPNManagerLogType message:@"isProviderZombie extension query failed" object:error];
          return [RACSignal return:[NSNumber numberWithBool:FALSE]];
      }];
}

// isPsiphonTunnelConnected returns a signal that when subscribed to sends "isTunnelConnected" query to the extension
// and then emits boolean response as NSNumber, or nil if extension is not active.
// Note: the returned signal emits FALSE if the extension returns empty response.
- (RACSignal<NSNumber *> *)isPsiphonTunnelConnected {
    return [[self queryActiveVPN:EXTENSION_QUERY_IS_TUNNEL_CONNECTED]
      catch:^RACSignal<NSNumber *> *(NSError *error) {
          [PsiFeedbackLogger warnWithType:VPNManagerLogType message:@"isTunnelConnected extension query failed" object:error];
          return [RACSignal return:[NSNumber numberWithBool:FALSE]];
      }];
}

// queryActiveVPN returns a signal that when subscribed to emits nil if the extension is not running,
// otherwise emits boolean value as NSNumber as the query response.
// Returned signal terminates with an error if the extension returns empty response.
- (RACSignal<NSNumber *> *)queryActiveVPN:(NSString *)query {

    return [[[[self deferredTunnelProviderManager]
      flattenMap:^RACSignal<NSString *> *(NETunnelProviderManager *providerManager) {

          NETunnelProviderSession *session = (NETunnelProviderSession *) providerManager.connection;

          if (!session) {
              // There is no tunnel provider, immediately completes the signal.
              return [RACSignal return:nil];
          }

          NEVPNStatus s = session.status;

          if (s == NEVPNStatusConnected ||
              s == NEVPNStatusConnecting ||
              s == NEVPNStatusReasserting ) {

              return [VPNManager sendProviderSessionMessage:query session:session];

          } else {
              // Tunnel is not active, immediately completes the signal.
              return [RACSignal return:nil];
          }
      }]
      map:^NSNumber *(NSString *response) {

          if ([response isEqualToString:EXTENSION_RESP_TRUE]) {
              return [NSNumber numberWithBool:TRUE];
          } else if ([response isEqualToString:EXTENSION_RESP_FALSE]) {
              return [NSNumber numberWithBool:FALSE];
          }

          return nil;
      }]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:[NSString stringWithFormat:@"queryActiveVPNOperation[%@]", query]];
}

// sendProviderSessionMessage:session: returns a signal that when subscribed to sends message to the tunnel provider
// and emits the response as NSString.
// If the response is empty, signal terminates with error code VPNManagerQueryNilResponse.
+ (RACSignal<NSString *> *)sendProviderSessionMessage:(NSString *_Nonnull)message session:(NETunnelProviderSession *_Nonnull)session {
    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {
        NSError *error;

        [session sendProviderMessage:[message dataUsingEncoding:NSUTF8StringEncoding]
                         returnError:&error
                     responseHandler:^(NSData *responseData) {
                         NSString *response = [[NSString alloc] initWithData:responseData
                                                                    encoding:NSUTF8StringEncoding];
                         LOG_DEBUG(@"extension query response: %@", response);
                         if (response && [response length] != 0) {
                             [subscriber sendNext:response];
                             [subscriber sendCompleted];
                         } else {
                             [subscriber sendError:[NSError errorWithDomain:VPNManagerErrorDomain
                                                                       code:VPNManagerQueryNilResponse]];
                         }
                     }];

        if (error) {
            [PsiFeedbackLogger warnWithType:VPNManagerLogType message:@"failed to send tunnel provider message" object:error];
            [subscriber sendError:error];
        }

        return nil;
    }];
}

@end
