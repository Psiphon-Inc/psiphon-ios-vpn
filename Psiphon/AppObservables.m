//
//  AppObservables.m
//  Psiphon
//
//  Created by Amir Khan on 2020-01-27.
//  Copyright © 2020 Psiphon Inc. All rights reserved.
//

#import "AppObservables.h"
#import <ReactiveObjC.h>
#import "Logging.h"
#import "Psiphon-Swift.h"

@interface AppObservables ()

//// subscriptionStatus should only be sent events to from the main thread.
//// Emits type ObjcUserSubscription
@property (nonatomic, readwrite) RACReplaySubject<BridgedUserSubscription *> *subscriptionStatus;

@property (nonatomic, readwrite) RACReplaySubject<ObjcSubscriptionBarViewState *> *subscriptionBarStatus;

@property (nonatomic, readwrite) RACReplaySubject<BridgedPsiCashWidgetBindingType *> *psiCashWidgetViewModel;

@property (nonatomic, readwrite) RACReplaySubject<NSNumber *> *vpnStatus;

@property (nonatomic, readwrite) RACReplaySubject<NSNumber *> *vpnStartStopStatus;


@property (nonatomic, readwrite) RACReplaySubject<ObjcSettingsViewModel *> *settingsViewModel;

@property (nonatomic, readwrite) RACReplaySubject<Region *> *selectedServerRegion;

// Private properties
@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation AppObservables

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
        _subscriptionStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _subscriptionBarStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _psiCashWidgetViewModel = [RACReplaySubject replaySubjectWithCapacity:1];
        _vpnStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _vpnStartStopStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        _settingsViewModel = [RACReplaySubject replaySubjectWithCapacity:1];
        _selectedServerRegion = [RACReplaySubject replaySubjectWithCapacity:1];
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }
    return self;
}

- (void)dealloc {
    [self.compoundDisposable dispose];
}

// TODO! who calls, this? Why was it important?
- (void)appLaunched {
}

@end
