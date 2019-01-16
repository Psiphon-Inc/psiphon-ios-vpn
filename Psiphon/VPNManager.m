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
 *   `unsafeSubscribeOnSerialQueue` allows us to do that, with the caveat that if used improperly can easily
 *   result in dead-locks. Check the operator's documentation for more details.
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

        _restartRequired = FALSE;

        _restartRequired = FALSE;

        _serialQueue = [UnionSerialQueue createWithLabel:@"ca.psiphon.Psiphon.VPNManagerSerialQueue"];

        // Public properties.
        VPNManager *__weak weakSelf = self;

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
    VPNManager *__weak weakSelf = self;

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

- (void)setTunnelProviderManager:(NETunnelProviderManager *_Nullable)tunnelProviderManager {
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

        VPNManager *__weak weakSelf = self;

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

        VPNManager *__weak weakInstance = instance;

        // Adds loading VPN operation to `serialOperationQueue` before returning shared instance.
        __block RACDisposable *disposable = [[[VPNManager loadTunnelProviderManager]
          unsafeSubscribeOnSerialQueue:instance.serialQueue
                              withName:@"initOperation"]
          subscribeNext:^(NETunnelProviderManager *tunnelProvider) {
              instance.tunnelProviderManager = tunnelProvider;
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

- (RACSignal<NSNumber *> *)vpnConfigurationInstalled {
    return [[[self deferredTunnelProviderManager]
      map:^NSNumber *(NETunnelProviderManager *providerManager) {
          return @(providerManager != nil);
      }]
      unsafeSubscribeOnSerialQueue:self.serialQueue withName:@"vpnConfigurationInstalled"];
}

// fix as in fix the zombie state
- (RACSignal<NSNumber *> *)checkOrFixVPN {
    VPNManager *__weak weakSelf = self;

    return [[[[[self unsafeBooleanQueryActiveVPN:EXTENSION_QUERY_IS_PROVIDER_ZOMBIE
                                        throwError:FALSE]
      flattenMap:^RACSignal<NETunnelProviderManager *> *(NSNumber *_Nullable isZombie) {

          if ([isZombie boolValue]) {
              return [weakSelf unsafeStopVPN];
          } else {
              return [weakSelf deferredTunnelProviderManager];
          }
      }]
      map:^NSNumber *(NETunnelProviderManager *_Nullable providerManager) {
          BOOL extensionProcessRunning = FALSE;
          if (providerManager) {
              NEVPNStatus st = providerManager.connection.status;
              if (st != NEVPNStatusInvalid &&
                  st != NEVPNStatusDisconnecting &&
                  st != NEVPNStatusDisconnected) {
                      extensionProcessRunning = TRUE;
              }
          }
          return @(extensionProcessRunning);
      }]
      unsafeSubscribeOnSerialQueue:self.serialQueue withName:@"checkOrFixVPN"]
      deliverOnMainThread];
}

- (void)startTunnel {

    // Sends VPNStartStatusStart eagerly, since the signal is subscribed on the `serialOperationQueue`
    // and would only be updated at some indeterminate time in the future.
    [self.internalStartStatus sendNext:@(VPNStartStatusStart)];

    VPNManager *__weak weakSelf = self;

    __block RACDisposable *disposable = [[[[[[[[VPNManager loadTunnelProviderManager]
      flattenMap:^RACSignal<NETunnelProviderManager *> *(NETunnelProviderManager *_Nullable pm) {
          // Updates VPN configuration parameters if it already exists,
          // otherwise creates a new VPN configuration.
          return [weakSelf updateOrCreateVPNConfigurationAndSave:pm];
      }]
      flattenMap:^RACSignal<NETunnelProviderManager *> *(NETunnelProviderManager *_Nonnull pm) {

          NSError *error;
          NSDictionary *options = @{EXTENSION_OPTION_START_FROM_CONTAINER: EXTENSION_OPTION_TRUE};
          [pm.connection startVPNTunnelWithOptions:options andReturnError:&error];

          // Terminate subscription early if an error occurred.
          if (error) {
              return [RACSignal error:error];
          }

          // Enabling Connect On Demand only after starting the tunnel. Otherwise, a race
          // condition is created between call to `startVPNTunnelWithOptions` and Connect On Demand.
          pm.onDemandEnabled = TRUE;
          return [RACSignal return:pm];
      }]
      flattenMap:^RACSignal *(NETunnelProviderManager *_Nonnull providerManager) {
          return [RACSignal defer:providerManager
                    selectorWithErrorCallback:@selector(saveToPreferencesWithCompletionHandler:)];
      }]
      flattenMap:^RACSignal *(NETunnelProviderManager *_Nonnull providerManager) {
          return [RACSignal defer:providerManager
                    selectorWithErrorCallback:@selector(loadFromPreferencesWithCompletionHandler:)];
      }]
      doNext:^(NETunnelProviderManager *_Nonnull providerManager) {
          weakSelf.tunnelProviderManager = providerManager;
      }]
      unsafeSubscribeOnSerialQueue:self.serialQueue withName:@"startTunnelOperation"]
      subscribeError:^(NSError *error) {
          [PsiFeedbackLogger errorWithType:VPNManagerLogType message:@"failed to start"
                                    object:error];

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

    VPNManager *__weak weakSelf = self;

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

// Emits type `NETunnelProviderManager *_Nullable`.
- (RACSignal<NETunnelProviderManager *> *)unsafeStopVPN {
    VPNManager *__weak weakSelf = self;

    // Connect On Demand should be disabled first before stopping the VPN.
    return [[[self setConnectOnDemandEnabled:FALSE]
      flattenMap:^RACSignal *(NSNumber *x) {
          return [weakSelf deferredTunnelProviderManager];
      }]
      doNext:^(NETunnelProviderManager *_Nullable providerManager) {
          [providerManager.connection stopVPNTunnel];
      }];
}

- (void)stopVPN {
    VPNManager *__weak weakSelf = self;

    // Connect On Demand should be disabled first before stopping the VPN.
    __block RACDisposable *disposable = [[[self unsafeStopVPN]
      unsafeSubscribeOnSerialQueue:self.serialQueue
                          withName:@"stopVPNOperation"]
      subscribeError:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

- (void)restartVPNIfActive {

    VPNManager *__weak weakSelf = self;

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
- (void)reinstallVPNConfiguration {

    VPNManager *__weak weakSelf = self;

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
    VPNManager *__weak weakSelf = self;

    return [[self queryIsExtensionZombie]
      flattenMap:^RACSignal *(NSNumber *_Nullable isZombie) {
          if ([isZombie boolValue]) {
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

// setConnectOnDemandEnabled: returns a signal that when subscribed to updates
// `self.tunnelProviderManager.onDemandEnabled` property with the provided onDemandEnabled
// if different and then emits @TRUE on success and @FALSE on failure.
//
// If onDemandEnabled is not different from `self.tunnelProviderManager`, then the returned signal
// emits @TRUE and completes.
// All errors are caught and logged, and FALSE is emitted in their place.
//
// If `self.tunnelProviderManager` is nil, returned signal emits @FALSE ane completes.
// Returned signal never terminates with an error.
- (RACSignal<NSNumber *> *)setConnectOnDemandEnabled:(BOOL)onDemandEnabled {
    VPNManager *__weak weakSelf = self;

    return [[[VPNManager loadTunnelProviderManager]
      flattenMap:^RACSignal<NETunnelProviderManager *> *(NETunnelProviderManager *providerManager) {

          if (!providerManager) {
              return [RACSignal return:@FALSE];
          }

          // If the on demand state doesn't need to change, emit @(TRUE) immediately.
          if (providerManager.onDemandEnabled == onDemandEnabled) {
              return [RACSignal return:@TRUE];
          }

          providerManager.onDemandEnabled = onDemandEnabled;

          // Returned signal, saves and loads the tunnel provider manager.
          return [[[[RACSignal defer:providerManager
                    selectorWithErrorCallback:@selector(saveToPreferencesWithCompletionHandler:)]
            flattenMap:^RACSignal<NETunnelProviderManager *> *(NETunnelProviderManager *manager) {
                return [RACSignal defer:manager
                    selectorWithErrorCallback:@selector(loadFromPreferencesWithCompletionHandler:)];
            }]
            doNext:^(NETunnelProviderManager *manager) {
                weakSelf.tunnelProviderManager = manager;
            }]
            mapReplace:@TRUE];
      }]
      catch:^RACSignal *(NSError *error) {
          [PsiFeedbackLogger errorWithType:VPNManagerLogType
                                   message:@"error setting OnDemandEnabled"
                                    object:error];

          return [RACSignal return:@FALSE];
      }];
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

    VPNManager *__weak weakSelf = self;

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

    VPNManager *__weak weakSelf = self;

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

          // Reset Connect On Demand state.
          // To enable Connect On Demand for all, it should be enabled right before startTunnel is called
          // on the NETunnelProviderManager object.
          providerManager.onDemandEnabled = FALSE;

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

- (RACSignal<NSNumber *> *)queryIsExtensionZombie {
    return [[[self unsafeBooleanQueryActiveVPN:EXTENSION_QUERY_IS_PROVIDER_ZOMBIE
                                       throwError:FALSE]
            map:^NSNumber *(NSNumber *_Nullable value) {
                // Value is nil if extension is not running, or there was an error sending message.
                // We default to FALSE as the tunnel connected query response.
                if (value == nil) {
                    return @FALSE;
                }
                return value;
            }]
            unsafeSubscribeOnSerialQueue:self.serialQueue withName:@"queryIsExtensionZombie"];
}

- (RACSignal<NSNumber *> *)queryIsPsiphonTunnelConnected {
    return [[[self unsafeBooleanQueryActiveVPN:EXTENSION_QUERY_IS_TUNNEL_CONNECTED
                                       throwError:FALSE]
            map:^NSNumber *(NSNumber *_Nullable value) {
                // Value is nil if extension is not running, or there was an error sending message.
                // We default to FALSE as the tunnel connected query response.
                if (value == nil) {
                    return @FALSE;
                }
                return value;
            }]
           unsafeSubscribeOnSerialQueue:self.serialQueue withName:@"isPsiphonTunnelConnectedQuery"];
}

// Emits type `NSNumber *_Nullable`.
- (RACSignal<NSNumber *> *)queryIsNetworkReachable {
    return [[self unsafeBooleanQueryActiveVPN:EXTENSION_QUERY_IS_NETWORK_REACHABLE
                                      throwError:FALSE]
      unsafeSubscribeOnSerialQueue:self.serialQueue withName:@"isNetworkReachableQuery"];
}

// queryActiveVPN returns a signal that when subscribed to sends query to the extension
// and emits boolean result.
//
// If the extension is not running, the nil is emitted.
// Returned signal terminates with an error if the extension returns empty response.
- (RACSignal<NSNumber *> *)unsafeBooleanQueryActiveVPN:(NSString *)query
                                            throwError:(BOOL)throwError {

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
              s == NEVPNStatusReasserting) {

              // Catch all errors if throwError is FALSE.
              RACSignal *retSignal = [VPNManager sendProviderSessionMessage:query session:session];
              if (!throwError) {
                  retSignal = [retSignal catch:^RACSignal *(NSError *error) {
                      return [RACSignal return:nil];
                  }];
              }
              return retSignal;

          } else {
              // Tunnel is not active, emit nil and then complete.
              return [RACSignal return:nil];
          }
      }]
      map:^NSNumber *(NSString *response) {
          if ([response isEqualToString:EXTENSION_RESP_TRUE]) {
              return @TRUE;
          } else if ([response isEqualToString:EXTENSION_RESP_FALSE]) {
              return @FALSE;
          }
          return nil;
      }]
      doError:^(NSError *error) {
          [PsiFeedbackLogger warnWithType:VPNManagerLogType
                message:[NSString stringWithFormat:@"unsafeBooleanQueryActiveVPN[%@] Failed", query]
                 object:error];
      }];
}

// sendProviderSessionMessage:session: returns a signal that when subscribed to sends message to the tunnel provider
// and emits the response as NSString.
// If the response is empty, signal terminates with error code VPNManagerQueryNilResponse.
+ (RACSignal<NSString *> *)sendProviderSessionMessage:(NSString *_Nonnull)message
                                              session:(NETunnelProviderSession *_Nonnull)session {

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        PSIAssert(RACScheduler.currentScheduler != nil);
        RACScheduler *scheduler = RACScheduler.currentScheduler;
        RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

        NSError *error;

        [session sendProviderMessage:[message dataUsingEncoding:NSUTF8StringEncoding]
                         returnError:&error
                     responseHandler:^(NSData *responseData) {

                         // Schedule events on the same subscription scheduler.
                         [compoundDisposable addDisposable:[scheduler schedule:^{
                             NSString *response = [[NSString alloc] initWithData:responseData
                                                                     encoding:NSUTF8StringEncoding];

                             LOG_DEBUG(@"extension query response: %@", response);
                             if (response && [response length] != 0) {
                                 [subscriber sendNext:response];
                                 [subscriber sendCompleted];
                             } else {
                                 [subscriber sendError:
                                   [NSError errorWithDomain:VPNManagerErrorDomain
                                                       code:VPNManagerQueryNilResponse]];
                             }
                         }]];
                     }];

        if (error) {
            [PsiFeedbackLogger warnWithType:VPNManagerLogType
                                    message:@"failed to send tunnel provider message"
                                     object:error];
            [subscriber sendError:error];
        }

        return compoundDisposable;
    }];
}

@end
