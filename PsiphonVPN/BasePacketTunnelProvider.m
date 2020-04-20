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

#import <Foundation/Foundation.h>
#import "BasePacketTunnelProvider.h"
#import "SharedConstants.h"
#import "PsiFeedbackLogger.h"
#import "FileUtils.h"
#import "RACReplaySubject.h"
#import "NSError+Convenience.h"
#import "Asserts.h"
#import "PsiphonDataSharedDB.h"
#import "Logging.h"

NSErrorDomain _Nonnull const BasePsiphonTunnelErrorDomain = @"BasePsiphonTunnelErrorDomain";

PsiFeedbackLogType const BasePacketTunnelProviderLogType = @"BasePacketTunnelProvider";

@interface BasePacketTunnelProvider ()

@property (nonatomic, readwrite) ExtensionStartMethodEnum extensionStartMethod;

@property (nonatomic, readwrite) BOOL VPNStarted;

@property (nonatomic, readwrite) PsiphonDataSharedDB *sharedDB;

@end

@implementation BasePacketTunnelProvider {
    // Pointer to startTunnelWithOptions completion handler.
    // NOTE: value is expected to be nil after completion handler has been called.
    void (^vpnStartCompletionHandler)(NSError *__nullable error);
}

- (instancetype)init {
    self = [super init];
    if (self) {

        int pid = [[NSProcessInfo processInfo] processIdentifier];
        [PsiFeedbackLogger infoWithType:BasePacketTunnelProviderLogType json:@{@"Event": @"Init",
                                                                               @"PID":@(pid)}];

       _vpnStartedSignal = [RACReplaySubject replaySubjectWithCapacity:1];
       _sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    }
    return self;
}

/**
 * Subclasses should not override this function.
 */
- (void)startTunnelWithOptions:(nullable NSDictionary<NSString *, NSObject *> *)options
             completionHandler:(void (^)(NSError *__nullable error))completionHandler {

    @synchronized (self) {

        // Determine if the extension jetsammed previously to this start.
        BOOL previouslyJetsammed = [self.sharedDB getExtensionJetsammedBeforeStopFlag];

         // Sets the crash flag. This flag is reset when `stopTunnelWithReason:completionHandler:` is called.
        [self.sharedDB setExtensionJetsammedBeforeStopFlag:TRUE];

        if (previouslyJetsammed) {
            [self.sharedDB incrementJetsamCounter];
            [PsiFeedbackLogger errorWithType:BasePacketTunnelProviderLogType
                                        json:@{@"JetsamCount": @([self.sharedDB getJetsamCounter])}];
        }

        // Creates boot test file used for testing if device is unlocked since boot.
        // A boot test file is a file with protection type NSFileProtectionCompleteUntilFirstUserAuthentication.
        // NOTE: it is assumed that this file is first created while the device is in an unlocked state,
        //       since file with such protection level cannot be created while device is still locked from boot.
        if (![self createBootTestFile]) {
            // Undefined behaviour wrt. Connect On Demand. Fail fast.
            [PsiFeedbackLogger error:@"Failed to create/check for boot test file."];
        }

        // List of paths to downgrade file protection to NSFileProtectionNone. The list could contain files or directories.
        NSArray<NSString *> *paths = @[
          // Note that this directory is not accessible in the container.
          [[[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] lastObject] path],
          // Shared container, containing logs and other data.
          [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path],
        ];

        // Set file protection of all files needed by the extension and Psiphon tunnel framework to NSFileProtectionNone.
        // This is required in order for "Connect On Demand" to work.
        if (![FileUtils downgradeFileProtectionToNone:paths withExceptions:@[ [self getBootTestFilePath] ]]) {
            // Undefined behaviour wrt. Connect On Demand. Fail fast.
            [PsiFeedbackLogger error:@"Failed to set file protection."];
        }

    #if DEBUG
        [FileUtils listDirectory:paths[0] resource:@"Library" recursively:YES];
        [FileUtils listDirectory:paths[1] resource:@"Shared container" recursively:YES];
    #endif

        BOOL tunnelStartedFromContainerRecently = FALSE;
        NSDate *_Nullable lastTunnelStartTime = [self.sharedDB getContainerTunnelStartTime];
        if (lastTunnelStartTime) {
            NSTimeInterval time = [[NSDate date] timeIntervalSinceDate:[self.sharedDB getContainerTunnelStartTime]];
            tunnelStartedFromContainerRecently = (time < 5.0);
        }

        // Determine how the extension was started.
        // ExtensionStartMethodFromCrash priority should be after _FromBoot and _FromContainer.
        //
        if ([self isStartBootTestFileLocked]) {
            self.extensionStartMethod = ExtensionStartMethodFromBoot;

        } else if (tunnelStartedFromContainerRecently ||
                 [((NSString *)options[EXTENSION_OPTION_START_FROM_CONTAINER]) isEqualToString:EXTENSION_OPTION_TRUE]) {
            self.extensionStartMethod = ExtensionStartMethodFromContainer;

        } else if (previouslyJetsammed) {
            self.extensionStartMethod = ExtensionStartMethodFromCrash;

        } else {
            self.extensionStartMethod = ExtensionStartMethodOther;
        }

        LOG_DEBUG(@"startTunnel options: %@", [options descriptionInStringsFileFormat]);

        // Hold a reference to the completionHandler
        vpnStartCompletionHandler = completionHandler;

        // Start the tunnel.
        [(id <BasePacketTunnelProviderProtocol>)self startTunnelWithErrorHandler:^(NSError *error) {
            if (error) {
                self->vpnStartCompletionHandler(error);
                self->vpnStartCompletionHandler = nil;
            }
        }];

    }
}

/**
 * Subclasses should not override this method.
 */
- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completionHandler {
    @synchronized (self) {

        // Resets the extension crash flag, since the extension hasn't crashed until stop is called.
        [self.sharedDB setExtensionJetsammedBeforeStopFlag:FALSE];

        // Assumes stopTunnelWithReason called exactly once only after startTunnelWithOptions.completionHandler(nil)
        if (vpnStartCompletionHandler) {
            vpnStartCompletionHandler([NSError errorWithDomain:BasePsiphonTunnelErrorDomain
                                                          code:BasePsiphonTunnelErrorStoppedBeforeConnected]);
            vpnStartCompletionHandler = nil;
        }

        [(id <BasePacketTunnelProviderProtocol>)self stopTunnelWithReason:reason];

        completionHandler();
    }
}

- (BOOL)startVPN {

    @synchronized (self) {
        if (vpnStartCompletionHandler) {
            vpnStartCompletionHandler(nil);
            vpnStartCompletionHandler = nil;
            self.VPNStarted = TRUE;

            [self.vpnStartedSignal sendNext:nil];
            [self.vpnStartedSignal sendCompleted];

            return TRUE;
        }
        return FALSE;
    }
}

- (void)exitGracefully {

    @synchronized (self) {

        // This is a manual exit and not a jetsam.
        [self.sharedDB setExtensionJetsammedBeforeStopFlag:FALSE];

        // We want to only wait for a maximum of 5 seconds for the tunnel to stop.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
          dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            exit(1);
        });

        // Try to gracefully shutdown the tunnel to free up server resources quicker.
        [(id <BasePacketTunnelProviderProtocol>)self stopTunnelWithReason:NEProviderStopReasonNone];

        exit(1);
    }
}

#pragma mark - Handling app messages

- (void)handleAppMessage:(NSData *)messageData completionHandler:(nullable void (^)(NSData *__nullable responseData))completionHandler {
    @synchronized (self) {

        if (!completionHandler) {
            return;
        }

        NSString *query = [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding];
        if ([EXTENSION_QUERY_TUNNEL_PROVIDER_STATE isEqualToString:query]) {
            
            id <BasePacketTunnelProviderProtocol> tunnelProvider = (id <BasePacketTunnelProviderProtocol>)self;
            NSDictionary *responseDict = @{
                @"isZombie": [tunnelProvider isNEZombie],
                @"isPsiphonTunnelConnected": [tunnelProvider isTunnelConnected],
                @"isNetworkReachable": [tunnelProvider isNetworkReachable]
            };
            
            NSError *err;
            // The resulting output will be UTF-8 encoded.
            NSData *output = [NSJSONSerialization dataWithJSONObject:responseDict
                                                             options:kNilOptions
                                                               error:&err];
            completionHandler(output);
            return;
        }

        // iOS always expects completionHandler to be called.
        completionHandler(nil);
    }
}

#pragma mark - Boot test

- (NSString *)getBootTestFilePath {
    return [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path]
      stringByAppendingPathComponent:BOOT_TEST_FILE_NAME];
}

/**
 * isDeviceLocked checks if boot file is encrypted as a proxy for whether the device is locked.
 * @return TRUE is device is locked from boot, FALSE otherwise.
 */
- (BOOL)isDeviceLocked {
    return [self isStartBootTestFileLocked];
}

- (BOOL)isStartBootTestFileLocked {
    FILE *fp = fopen([[self getBootTestFilePath] UTF8String], "r");
    if (fp == NULL && errno == EPERM) {
        return TRUE;
    }
    if (fp != NULL) fclose(fp);
    return FALSE;
}

- (BOOL)createBootTestFile {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Need to check for existence of file, even though the extension may not have permission to open it.
    if (![fm fileExistsAtPath:[self getBootTestFilePath]]) {
        return [fm createFileAtPath:[self getBootTestFilePath]
                           contents:[@"boot_test_file" dataUsingEncoding:NSUTF8StringEncoding]
                         attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}];
    }

    NSError *err;
    NSDictionary<NSFileAttributeKey, id> *attrs = [fm attributesOfItemAtPath:[self getBootTestFilePath] error:&err];
    if (err) {
        [PsiFeedbackLogger error:@"Failed to get file attributes for boot test file. (%@)", err];
        return FALSE;
    } else if (![attrs[NSFileProtectionKey] isEqualToString:NSFileProtectionCompleteUntilFirstUserAuthentication]) {
        [PsiFeedbackLogger error:@"Boot test file has it's protection level changed to (%@)", attrs[NSFileProtectionKey]];
        return FALSE;
    }

    return TRUE;
}

#pragma mark - Helper methods

- (void)displayMessage:(NSString *_Nonnull)message {
    [self displayMessage:message completionHandler:^(BOOL success) {
        // Do nothing.
    }];
}

- (NSString *)extensionStartMethodTextDescription {
    switch (self.extensionStartMethod) {
        case ExtensionStartMethodFromContainer: return @"Container";
        case ExtensionStartMethodFromBoot: return @"Boot";
        case ExtensionStartMethodFromCrash: return @"Crash";
        case ExtensionStartMethodOther: return @"Other";
        default: PSIAssert(FALSE);
    }

    return @"Unknown";
}

@end
