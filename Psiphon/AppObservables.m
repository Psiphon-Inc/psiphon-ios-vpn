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
}

@end
