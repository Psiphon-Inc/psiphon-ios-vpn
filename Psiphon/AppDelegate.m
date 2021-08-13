/*
 * Copyright (c) 2015, Psiphon Inc.
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

#import <ReactiveObjC/RACTuple.h>
#import <NetworkExtension/NetworkExtension.h>
#import <ReactiveObjC/RACScheduler.h>
#import <ReactiveObjC/RACUnit.h>
#import <ReactiveObjC/NSNotificationCenter+RACSupport.h>
#import <stdatomic.h>
#import "AppDelegate.h"
#import "AppInfo.h"
#import "EmbeddedServerEntries.h"
#import "IAPViewController.h"
#import "Logging.h"
#import "Notifier.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonConfigReader.h"
#import "PsiphonDataSharedDB.h"
#import "RootContainerController.h"
#import "SharedConstants.h"
#import "UIAlertController+Additions.h"
#import "Logging.h"
#import "NEBridge.h"
#import "DispatchUtils.h"
#import "PsiFeedbackLogger.h"
#import "RACMulticastConnection.h"
#import "RACSignal.h"
#import "RACSignal+Operations2.h"
#import "NSError+Convenience.h"
#import "RACCompoundDisposable.h"
#import "RACSignal+Operations.h"
#import "RACReplaySubject.h"
#import "Asserts.h"
#import "ContainerDB.h"
#import "AppObservables.h"
#import <PsiphonTunnel/PsiphonTunnel.h>
#import "RegionAdapter.h"
#import "SettingsViewController.h"

PsiFeedbackLogType const RewardedVideoLogType = @"RewardedVideo";

@interface AppDelegate () <NotifierObserver>

// Private properties
@property (nonatomic) RACCompoundDisposable *compoundDisposable;
@property (nonatomic) PsiphonDataSharedDB *sharedDB;

@end

@implementation AppDelegate {
    BOOL pendingStartStopSignalCompletion;
    RootContainerController *rootContainerController;
    RACDisposable *_Nullable rewardedVideoAdDisposable;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Sets up debug flags early in the application lifecycle.
        [SwiftDelegate setupDebugFlags];

        pendingStartStopSignalCompletion = FALSE;
        _sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:PsiphonAppGroupIdentifier];
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }
    return self;
}

- (void)dealloc {
    [self->rewardedVideoAdDisposable dispose];
    [self.compoundDisposable dispose];
}

+ (AppDelegate *)sharedAppDelegate {
    return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

# pragma mark - Lifecycle methods

- (BOOL)application:(UIApplication *)application
willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // Immediately register to receive notifications from the Network Extension process.
    [[Notifier sharedInstance] registerObserver:self callbackQueue:dispatch_get_main_queue()];

    // Initializes PsiphonClientCommonLibrary.
    [PsiphonClientCommonLibraryHelpers initializeDefaultsForPlistsFromRoot:@"Root.inApp"];

    return [SwiftDelegate.bridge applicationWillFinishLaunching:application
                                                  launchOptions:launchOptions
                                                     objcBridge:(id<ObjCBridgeDelegate>) self];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    LOG_DEBUG();
    
    [SwiftDelegate.bridge applicationDidFinishLaunching:application];
    
    [AppObservables.shared appLaunched];

    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    // Sets strict window size for iOS app on Mac.
    if ([AppInfo isiOSAppOnMac] == TRUE) {
        
        if (@available(iOS 13.0, *)) {
            
            if (self.window.windowScene.sizeRestrictions == nil) {
                @throw [NSException exceptionWithName:@"Invalid State"
                                               reason:@"windowScence.sizeRestrictions is nil"
                                             userInfo:nil];
            }
            
            UISceneSizeRestrictions *sizeRestrictions = self.window.windowScene.sizeRestrictions;
            sizeRestrictions.maximumSize = CGSizeMake(468, 736);
            sizeRestrictions.minimumSize = CGSizeMake(468, 736);
            
        }

    }

    rootContainerController = [[RootContainerController alloc] init];
    self.window.rootViewController = rootContainerController;

    // UIKit always waits for application:didFinishLaunchingWithOptions:
    // to return before making the window visible on the screen.
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    LOG_DEBUG();
    
    [SwiftDelegate.bridge applicationDidBecomeActive:application];

    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [SwiftDelegate.bridge applicationWillResignActive:application];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    LOG_DEBUG();
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.

    [[UIApplication sharedApplication] ignoreSnapshotOnNextApplicationLaunch];
    [SwiftDelegate.bridge applicationDidEnterBackground:application];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    LOG_DEBUG();
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    [SwiftDelegate.bridge applicationWillEnterForeground:application];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    LOG_DEBUG();
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [SwiftDelegate.bridge applicationWillTerminate:application];
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {

    return [SwiftDelegate.bridge application:app open:url options:options];
}

#pragma mark - VPN start stop

// Emitted NSNumber is of type VPNIntent.
- (RACSignal<RACTwoTuple<NSNumber*, SwitchedVPNStartStopIntent*> *> *)startOrStopVPNSignal {
    
    return [[[RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {
        [[SwiftDelegate.bridge switchVPNStartStopIntent]
         then:^id _Nullable(SwitchedVPNStartStopIntent * newIntent) {
            if (newIntent == nil) {
                [NSException raise:@"nil found"
                            format:@"expected non-nil SwitchedVPNStartStopIntent value"];
            }
            
            [subscriber sendNext:newIntent];
            [subscriber sendCompleted];
            return nil;
        }];
        
        return nil;
    }] doNext:^(SwitchedVPNStartStopIntent *value) {
        dispatch_async_main(^{
            [SwiftDelegate.bridge sendNewVPNIntent:value];
        });
    }] deliverOnMainThread];
}

- (void)startStopVPN {
    AppDelegate *__weak weakSelf = self;
    
    if (pendingStartStopSignalCompletion == TRUE) {
        return;
    }
    pendingStartStopSignalCompletion = TRUE;

    __block RACDisposable *disposable = [[self startOrStopVPNSignal]
      subscribeError:^(NSError *error) {
        [weakSelf.compoundDisposable removeDisposable:disposable];
      }
      completed:^{
        if (NSThread.isMainThread != TRUE) {
            [NSException raise:@"MainThreadCheck"
                        format:@"Expected callback on main-thread"];
        }
        AppDelegate *__strong strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf.compoundDisposable removeDisposable:disposable];
            strongSelf->pendingStartStopSignalCompletion = FALSE;
        }
      }];

    [self.compoundDisposable addDisposable:disposable];
}

#pragma mark -

- (void)reloadMainViewControllerAndImmediatelyOpenSettings {
    LOG_DEBUG();
    [rootContainerController reloadMainViewControllerAndImmediatelyOpenSettings];
}

- (void)reloadOnboardingViewController {
    LOG_DEBUG();
    [rootContainerController reloadOnboardingViewController];
}

#pragma mark - Notifier callback

- (void)onMessageReceived:(NotifierMessage)message {
    LOG_DEBUG(@"Received notification: '%@'", message);
    [SwiftDelegate.bridge networkExtensionNotification:message];
}

@end

#pragma mark - ObjCBridgeDelegate

@interface UIViewController (DimissViewController)
// Helper function for dismissing a ViewController in the hierarchy.
- (void)dismissViewControllerType:(Class)viewControllerClass
                       completion:(void (^ _Nullable)(void))completion;
@end

@implementation UIViewController (DismissViewController)

- (void)dismissViewControllerType:(Class)viewControllerClass
                       completion:(void (^ _Nullable)(void))completion
{
    if ([self isKindOfClass:viewControllerClass]) {
        [self dismissViewControllerAnimated:true completion:completion];
        return;
    }

    for (UIViewController *childVC in self.childViewControllers) {
        [childVC dismissViewControllerType:viewControllerClass completion:completion];
    }

    [self.presentedViewController dismissViewControllerType:viewControllerClass
                                                 completion:completion];
}

@end

@interface AppDelegate (SwiftExtensions) <ObjCBridgeDelegate>
@end

@implementation AppDelegate (SwiftExtensions)

- (void)onPsiCashWidgetViewModelUpdate:(BridgedPsiCashWidgetBindingType *)balance {
    [AppObservables.shared.psiCashWidgetViewModel sendNext:balance];
}

- (void)onSubscriptionStatus:(BridgedUserSubscription * _Nonnull)status {
    [AppObservables.shared.subscriptionStatus sendNext:status];
}

- (void)onSubscriptionBarViewStatusUpdate:(ObjcSubscriptionBarViewState *)status {
    [AppObservables.shared.subscriptionBarStatus sendNext: status];
}

- (void)onVPNStatusDidChange:(NEVPNStatus)status {
    [AppObservables.shared.vpnStatus sendNext:@(status)];
}

- (void)onVPNStateSyncError:(NSString *)userErrorMessage {
    UIAlertController *ac = [UIAlertController
                             alertControllerWithTitle:[UserStrings Error_title]
                             message:userErrorMessage
                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:[UserStrings OK_button_title]
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil];
    
    UIAlertAction *reinstallConfigAction = [UIAlertAction
                                            actionWithTitle:[UserStrings Reinstall_vpn_config]
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [SwiftDelegate.bridge reinstallVPNConfig];
    }];
    [ac addAction:okAction];
    [ac addAction:reinstallConfigAction];
    [ac presentFromTopController];
}

- (void)onVPNStartStopStateDidChange:(VPNStartStopStatus)status {
    [AppObservables.shared.vpnStartStopStatus sendNext:@(status)];
}

- (void)onReachabilityStatusDidChange:(ReachabilityStatus)status {
    [AppObservables.shared.reachabilityStatus sendNext:@(status)];
}

- (void)onSettingsViewModelDidChange:(ObjcSettingsViewModel *)model {
    [AppObservables.shared.settingsViewModel sendNext:model];
}

- (void)dismissWithScreen:(enum DismissibleScreen)screen
               completion:(void (^ _Nullable)(void))completion
{
    switch (screen) {
        case DismissibleScreenPsiCash:
            [self.window.rootViewController dismissViewControllerType:PsiCashViewController.class
                                                           completion:completion];
            break;
        case DismissibleScreenSettings:
            [self.window.rootViewController dismissViewControllerType:SettingsViewController.class
                                                           completion:completion];
            break;
    }
}

- (void)presentSubscriptionIAPViewController {
    IAPViewController* iapViewController = [[IAPViewController alloc] init];
    iapViewController.openedFromSettings = FALSE;
    
    UINavigationController* navCtrl = [[UINavigationController alloc]
                                       initWithRootViewController:iapViewController];
    
    [[SwiftDelegate.bridge getTopActiveViewController] presentViewController:navCtrl
                                                                    animated:TRUE
                                                                  completion:nil];
}

/*!
 * @brief Updates available egress regions from embedded server entries.
 *
 * This function should only be called once per app version on first launch.
 */
- (void)updateAvailableEgressRegionsOnFirstRunOfAppVersion {
    NSString *embeddedServerEntriesPath = PsiphonConfigReader.embeddedServerEntriesPath;
    NSError *e;
    NSSet<NSString*> *embeddedEgressRegions = [EmbeddedServerEntries egressRegionsFromFile:embeddedServerEntriesPath
                                                                                     error:&e];

    // Note: server entries may have been decoded before the error occurred and
    // they will be present in the result.
    if (e != nil) {
        [PsiFeedbackLogger error:e message:@"Error decoding embedded server entries"];
    }

    if (embeddedEgressRegions != nil && [embeddedEgressRegions count] > 0) {
        LOG_DEBUG("Available embedded egress regions: %@.", embeddedEgressRegions);
        ContainerDB *containerDB = [[ContainerDB alloc] init];
        [containerDB setEmbeddedEgressRegions:[NSArray arrayWithArray:[embeddedEgressRegions allObjects]]];
    } else {
        [PsiFeedbackLogger error:@"Error no egress regions found in %@.", embeddedServerEntriesPath];
    }
}

@end
