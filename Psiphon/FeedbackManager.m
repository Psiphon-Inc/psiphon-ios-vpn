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

#import "FeedbackManager.h"
#import "AppDelegate.h"
#import "DispatchUtils.h"
#import "FeedbackUpload.h"
#import "IAPStoreHelper.h"
#import "MBProgressHUD.h"
#import "PsiFeedbackLogger.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "UIAlertController+Delegate.h"
#import <stdatomic.h>

@implementation FeedbackManager {
    MBProgressHUD *uploadProgressAlert;
    PsiphonTunnel *inactiveTunnel;
    _Atomic(int32_t) numUploadsInFlight;
}

#pragma mark - TunneledAppDelegate protocol implementation

- (void)onDiagnosticMessage:(NSString *_Nonnull)message withTimestamp:(NSString *_Nonnull)timestamp {
    if ([message isEqualToString:@"Feedback upload successful"]) {
        [self uploadCompletedSuccessfully];
    } else if ([message containsString:@"Feedback upload error"]) {
        [self uploadFailed];
    }
    
    [PsiFeedbackLogger logNoticeWithType:@"FeedbackUpload" message:message timestamp:timestamp];
}

/*!
 * If Psiphon config string could not be created, corrupt message alert is displayed
 * to the user.
 * This method can be called from background-thread.
 * @return Psiphon config string, or nil of config string could not be created.
 */
- (NSString * _Nullable)getPsiphonConfig {
    NSString *bundledConfigStr = [PsiphonClientCommonLibraryHelpers getPsiphonBundledConfig];
    
    // Always parses the config string to ensure its valid, even the config string will not be modified.
    NSData *jsonData = [bundledConfigStr dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    NSDictionary *readOnly = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&err];
    
    // Return bundled config as is if user doesn't have an active subscription
    if(![IAPStoreHelper hasActiveSubscriptionForNow] && !err) {
        return bundledConfigStr;
    }
    
    // Otherwise override sponsor ID
    if (err) {
        [PsiFeedbackLogger error:@"%@", [NSString stringWithFormat:@"Failed to parse config JSON: %@", err.description]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self displayCorruptSettingsFileAlert];
        });
        return nil;
    }
    
    NSMutableDictionary *mutableConfigCopy = [readOnly mutableCopy];
    
    NSDictionary *readOnlySubscriptionConfig = readOnly[@"subscriptionConfig"];
    if(readOnlySubscriptionConfig && readOnlySubscriptionConfig[@"SponsorId"]) {
        mutableConfigCopy[@"SponsorId"] = readOnlySubscriptionConfig[@"SponsorId"];
    }
    
#if DEBUG
    // Ensure diagnostic notices are emitted when debugging
    mutableConfigCopy[@"EmitDiagnosticNotices"] = [NSNumber numberWithBool:YES];
#endif
    
    jsonData  = [NSJSONSerialization dataWithJSONObject:mutableConfigCopy options:0 error:&err];
    
    if (err) {
        [PsiFeedbackLogger error:@"%@", [NSString stringWithFormat:@"Failed to create JSON data from config object: %@", err.description]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self displayCorruptSettingsFileAlert];
        });
        return nil;
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString * _Nullable)getEmbeddedServerEntries {
    return nil;
}

#pragma mark - FeedbackViewControllerDelegate protocol implementation

- (void)userSubmittedFeedback:(NSUInteger)selectedThumbIndex comments:(NSString *)comments email:(NSString *)email uploadDiagnostics:(BOOL)uploadDiagnostics {
    [self uploadInFlight];
    // Ensure psiphon data is populated with latest logs
    // TODO: should this be a delegate method of Psiphon Data in shared library
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *psiphonConfig = [self getPsiphonConfig];
        if (!psiphonConfig) {
            // Corrupt settings file. Return early.
            return;
        }
        
        NSArray<DiagnosticEntry *> *diagnosticEntries = [[[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER] getAllLogs];
        
        __weak FeedbackManager *weakSelf = self;
        SendFeedbackHandler sendFeedbackHandler = ^(NSString *jsonString, NSString *pubKey, NSString *uploadServer, NSString *uploadServerHeaders) {
            if (inactiveTunnel == nil) {
                // Lazily allocate PsiphonTunnel instance
                inactiveTunnel = [PsiphonTunnel newPsiphonTunnel:weakSelf]; // TODO: we need to update PsiphonTunnel framework to not require this and fix this warning
            }
            [inactiveTunnel sendFeedback:jsonString publicKey:pubKey uploadServer:uploadServer uploadServerHeaders:uploadServerHeaders];
        };
        
        NSError *err = [FeedbackUpload generateAndSendFeedback:selectedThumbIndex
                                                     buildInfo:[PsiphonTunnel getBuildInfo]
                                                      comments:comments
                                                         email:email
                                            sendDiagnosticInfo:uploadDiagnostics
                                             withPsiphonConfig:psiphonConfig
                                            withClientPlatform:@"ios-vpn"
                                            withConnectionType:[self getConnectionType]
                                                  isJailbroken:[JailbreakCheck isDeviceJailbroken]
                                           sendFeedbackHandler:sendFeedbackHandler
                                             diagnosticEntries:diagnosticEntries];
        
        if (err != nil) {
            // Feedback upload was never started
            [self uploadFailed];
        }
    });
}

- (void)userPressedURL:(NSURL *)URL {
    [[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:nil];
}

#pragma mark - Helpers

- (void)showUploadInProgressView {
    uploadProgressAlert = [MBProgressHUD showHUDAddedTo:AppDelegate.getTopMostViewController.view animated:YES];
    uploadProgressAlert.mode = MBProgressHUDModeIndeterminate;
    uploadProgressAlert.label.text = NSLocalizedStringWithDefaultValue(@"FEEDBACK_UPLOAD_IN_PROGRESS_MESSAGE", nil, [NSBundle mainBundle], @"Sending feedback…", @"Alert dialog title indicating to the user that their feedback is being encrypted and securely uploaded to Psiphon's servers.");
    uploadProgressAlert.label.adjustsFontSizeToFitWidth = YES;
    uploadProgressAlert.label.numberOfLines = 0;
    uploadProgressAlert.backgroundView.style = MBProgressHUDBackgroundStyleSolidColor;
    uploadProgressAlert.backgroundView.color = [UIColor colorWithWhite:0.1f alpha:0.1f];
    [uploadProgressAlert.button setTitle:NSLocalizedStringWithDefaultValue(@"FEEDBACK_UPLOAD_IN_PROGRESS_BACKGROUND_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Background", @"Title of button on alert view which shows the progress of the users feedback being uploaded to Psiphon's servers. Hitting this button dismisses the alert and the upload continues in the background.") forState:UIControlStateNormal];
    [uploadProgressAlert.button addTarget:self action:@selector(removeUploadInProgressView) forControlEvents:UIControlEventTouchUpInside];
}

- (void)removeUploadInProgressView {
    dispatch_async_main(^{
        [uploadProgressAlert hideAnimated:YES];
        uploadProgressAlert = nil;
    });
}

- (BOOL)progressViewHasBeenDismissed {
    return uploadProgressAlert == nil;
}

- (void)uploadInFlight {
    atomic_fetch_add(&numUploadsInFlight, 1);
    dispatch_async_main(^{
        [self showUploadInProgressView];
    });
}

- (void)uploadCompletedSuccessfully {
    atomic_fetch_sub(&numUploadsInFlight, 1);
    BOOL lastUploadCompleted = atomic_load(&numUploadsInFlight) == 0;
    
    if (lastUploadCompleted && uploadProgressAlert != nil) {
        [self removeUploadInProgressView];
        dispatch_async_main(^{
            [UIAlertController presentSimpleAlertWithTitle:NSLocalizedStringWithDefaultValue(@"FEEDBACK_UPLOAD_SUCCESSFUL_TITLE", nil, [NSBundle mainBundle], @"Feedback uploaded successfully", @"Alert dialog title indicating to the user that their feedback has been successfully uploaded to Psiphon's servers.")
                                                   message:NSLocalizedStringWithDefaultValue(@"FEEDBACK_UPLOAD_SUCCESSFUL_MESSAGE", nil, [NSBundle mainBundle], @"Thank you for helping improve Psiphon!", @"Alert dialog message thanking the user for helping improve the Psiphon network by submitting their feedback.")
                                            preferredStyle:UIAlertControllerStyleAlert
                                                 okHandler:nil];
        });
    }
}

- (void)uploadFailed {
    atomic_fetch_sub(&numUploadsInFlight, 1);
    BOOL lastUploadCompleted = atomic_load(&numUploadsInFlight) == 0;
    
    if (lastUploadCompleted && uploadProgressAlert != nil) {
        [self removeUploadInProgressView];
    }
    
#if DEBUG
    dispatch_async_main(^{
        [UIAlertController presentSimpleAlertWithTitle:NSLocalizedStringWithDefaultValue(@"FEEDBACK_UPLOAD_FAILED_TITLE", nil, [NSBundle mainBundle], @"Feedback upload failed", @"Alert dialog title indicating to the user that the app has failed to upload their feedback to Psiphon's servers.")
                                               message:NSLocalizedStringWithDefaultValue(@"FEEDBACK_UPLOAD_FAILED_MESSAGE", nil, [NSBundle mainBundle], @"An error occured while uploading your feedback. Please try again. Your feedback helps us improve the Psiphon network.", @"Alert dialog message indicating to the user that the app has failed to upload their feedback and that they should try again. ")
                                        preferredStyle:UIAlertControllerStyleAlert
                                             okHandler:nil]; // TODO: add retry button
    });
#endif
}

// Get connection type for feedback
- (NSString*)getConnectionType {
    
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    
    NetworkStatus status = [reachability currentReachabilityStatus];
    
    if(status == NotReachable)
    {
        return @"none";
    }
    else if (status == ReachableViaWiFi)
    {
        return @"WIFI";
    }
    else if (status == ReachableViaWWAN)
    {
        return @"mobile";
    }
    
    return @"error";
}

- (void)displayCorruptSettingsFileAlert {
    [UIAlertController presentSimpleAlertWithTitle:NSLocalizedStringWithDefaultValue(@"CORRUPT_SETTINGS_ALERT_TITLE", nil, [NSBundle mainBundle], @"Corrupt Settings", @"Alert dialog title of alert which informs the user that the settings file in the app is corrupt.")
                                           message:NSLocalizedStringWithDefaultValue(@"CORRUPT_SETTINGS_MESSAGE", nil, [NSBundle mainBundle], @"Your app settings file appears to be corrupt. Try reinstalling the app to repair the file.", @"Alert dialog message informing the user that the settings file in the app is corrupt, and that they can potentially fix this issue by re-installing the app.")
                                    preferredStyle:UIAlertControllerStyleAlert
                                         okHandler:nil];
}

@end

