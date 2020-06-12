//
//  AppObservables.m
//  Psiphon
//
//  Created by Amir Khan on 2020-01-27.
//  Copyright © 2020 Psiphon Inc. All rights reserved.
//

#import <PsiphonTunnel/Reachability.h>
#import "AppObservables.h"
#import <ReactiveObjC.h>
#import "Logging.h"
#import "Psiphon-Swift.h"

@interface AppObservables ()

@property (nonatomic, nullable, readwrite) RACMulticastConnection<AppEvent *> *appEvents;

//// subscriptionStatus should only be sent events to from the main thread.
//// Emits type ObjcUserSubscription
@property (nonatomic, readwrite) RACReplaySubject<BridgedUserSubscription *> *subscriptionStatus;

@property (nonatomic, readwrite) RACReplaySubject<ObjcSubscriptionBarViewState *> *subscriptionBarStatus;

@property (nonatomic, readwrite) RACReplaySubject<BridgedBalanceViewBindingType *> *psiCashBalance;

@property (nonatomic, readwrite) RACReplaySubject<NSDate *> *speedBoostExpiry;

@property (nonatomic, readwrite) RACReplaySubject<NSNumber *> *vpnStatus;

@property (nonatomic, readwrite) RACReplaySubject<NSNumber *> *vpnStartStopStatus;

@property (nonatomic, readwrite) RACReplaySubject<NSNumber *> *reachabilityStatus;

// Private properties
@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation AppObservables {
    Reachability *reachability;
}

+ (instancetype)shared {
    static AppObservables *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        reachability = [Reachability reachabilityForInternetConnection];

        _subscriptionStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _subscriptionBarStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _psiCashBalance = [RACReplaySubject replaySubjectWithCapacity:1];
        _speedBoostExpiry = [RACReplaySubject replaySubjectWithCapacity:1];
        _vpnStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _vpnStartStopStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _reachabilityStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }
    return self;
}

- (void)dealloc {
    [reachability stopNotifier];
    [self.compoundDisposable dispose];
}

- (void)appLaunched {
    [reachability startNotifier];

    // Infinite hot signal - emits an item after the app delegate applicationWillEnterForeground: is called.
    RACSignal *appWillEnterForegroundSignal = [[NSNotificationCenter defaultCenter]
                                               rac_addObserverForName:UIApplicationWillEnterForegroundNotification object:nil];

    // Infinite cold signal - emits @(TRUE) when network is reachable, @(FALSE) otherwise.
    // Once subscribed to, starts with the current network reachability status.
    //
    RACSignal<NSNumber *> *reachabilitySignal = [[[[[NSNotificationCenter defaultCenter]
                                                    rac_addObserverForName:kReachabilityChangedNotification object:reachability]
                                                   map:^NSNumber *(NSNotification *note) {
        return @(((Reachability *) note.object).currentReachabilityStatus);
    }]
                                                  startWith:@([reachability currentReachabilityStatus])]
                                                 map:^NSNumber *(NSNumber *value) {
        NetworkStatus s = (NetworkStatus) [value integerValue];
        return @(s != NotReachable);
    }];

    // Infinite cold signal - emits @(TRUE) if user has an active subscription, @(FALSE) otherwise.
    // Note: Nothing is emitted if the subscription status is unknown.
    RACSignal<NSNumber *> *activeSubscriptionSignal =
    [[[AppObservables shared].subscriptionStatus
      filter:^BOOL(BridgedUserSubscription *status) {
        return status.state != BridgedSubscriptionStateUnknown;
    }] map:^NSNumber *(BridgedUserSubscription *status) {
        return @(status.state == BridgedSubscriptionStateActive);
    }];

    // Infinite cold signal - emits events of type @(TunnelState) for various tunnel events.
    // While the tunnel is being established or destroyed, this signal emits @(TunnelStateNeither).
    RACSignal<NSNumber *> *tunnelConnectedSignal =
    [self.vpnStatus map:^NSNumber *(NSNumber *value) {
        VPNStatus s = (VPNStatus) [value integerValue];
        
        if (s == VPNStatusConnected) {
            return @(TunnelStateTunneled);
        } else if (s == VPNStatusDisconnected || s == VPNStatusInvalid) {
            return @(TunnelStateUntunneled);
        } else {
            return @(TunnelStateNeither);
        }
    }];

    // NOTE: We have to be careful that ads are requested,
    //       loaded and the impression is registered all from the same tunneled/untunneled state.

    // combinedEventSignal is infinite cold signal - Combines all app event signals,
    // and create AppEvent object. The AppEvent emissions are as unique as `[AppEvent isEqual:]` determines.
    RACSignal<AppEvent *> *combinedEventSignals = [[[RACSignal
                                                     combineLatest:@[
                                                         reachabilitySignal,
                                                         activeSubscriptionSignal,
                                                         tunnelConnectedSignal
                                                     ]]
                                                    map:^AppEvent *(RACTuple *eventsTuple) {

        AppEvent *e = [[AppEvent alloc] init];
        e.networkIsReachable = [((NSNumber *) eventsTuple.first) boolValue];
        e.subscriptionIsActive = [((NSNumber *) eventsTuple.second) boolValue];
        e.tunnelState = (TunnelState) [((NSNumber *) eventsTuple.third) integerValue];
        return e;
    }]
                                                   distinctUntilChanged];

    // The underlying multicast signal emits AppEvent objects. The emissions are repeated if a "trigger" event
    // such as "appWillForeground" happens with source set to appropriate value.
    self.appEvents = [[[[RACSignal
         // Merge all "trigger" signals that cause the last AppEvent from `combinedEventSignals` to be emitted again.
         // NOTE: - It should be guaranteed that SourceEventStarted is always the first emission and that it will
         //         be always after the Ad SDKs have been initialized.
         //       - It should also be guaranteed that signals in the merge below are not the same as the signals
         //         in the `combinedEventSignals`. Otherwise we would have subscribed to the same signal twice,
         //         and since we're using the -combineLatestWith: operator, we will get the same emission repeated.
         merge:@[
             [RACSignal return:@(SourceEventStarted)],
             [appWillEnterForegroundSignal mapReplace:@(SourceEventAppForegrounded)]
         ]]
         combineLatestWith:combinedEventSignals]
         combinePreviousWithStart:nil
         reduce:^AppEvent *(RACTwoTuple<NSNumber *, AppEvent *> *_Nullable prev,
                          RACTwoTuple<NSNumber *, AppEvent *> *_Nonnull curr) {

        // Infers the source signal of the current emission.
        //
        // Events emitted by the signal that we combine with (`combinedEventSignals`) are unique,
        // and therefore the AppEvent state that is different between `prev` and `curr` is also the source.
        // If `prev` and `curr` AppEvent are the same, then the "trigger" signal is one of the merged signals
        // upstream.

        AppEvent *_Nullable pe = prev.second;
        AppEvent *_Nonnull ce = curr.second;

        if (pe == nil || [pe isEqual:ce]) {
            // Event source is not from the change in AppEvent properties and so not from `combinedEventSignals`.reachability
            ce.source = (SourceEvent) [curr.first integerValue];
        } else {

            // Infer event source based on changes in values.
            if (pe.networkIsReachable != ce.networkIsReachable) {
                ce.source = SourceEventReachability;

            } else if (pe.subscriptionIsActive != ce.subscriptionIsActive) {
                ce.source = SourceEventSubscription;

            } else if (pe.tunnelState != ce.tunnelState) {
                ce.source = SourceEventTunneled;
            }
        }

        return ce;
    }] multicast:[RACReplaySubject replaySubjectWithCapacity:1]];

#if DEBUG
    [self.compoundDisposable addDisposable:[self.appEvents.signal
                                            subscribeNext:^(AppEvent * _Nullable x) {
        LOG_DEBUG(@"\n%@", [x debugDescription]);
    }]];
#endif

    [self.compoundDisposable addDisposable:[self.appEvents connect]];
}

@end
