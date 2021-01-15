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

#import <UIKit/UIKit.h>

#import "AppInfo.h"
#import "Asserts.h"
#import "PsiphonConfigReader.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "UserDefaults.h"
#import <PsiphonTunnel/JailbreakCheck.h>

PsiFeedbackLogType const AppInfoLogType = @"AppInfo";

UserDefaultsKey const AppInfoFastLaneSnapShotBoolKey = @"FASTLANE_SNAPSHOT";

@implementation AppInfo

+ (NSString*)appVersion {
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    if (appVersion == NULL) {
        return @"unknown";
    }
    return appVersion;
}

+ (NSString*)clientRegion {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:PsiphonAppGroupIdentifier];
    return [sharedDB emittedClientRegion];
}

+ (NSString*)propagationChannelId {
    NSDictionary *config = [PsiphonConfigReader fromConfigFile].config;
    if (!config) {
        // PsiphonConfigReader has logged an error
        return nil;
    }
    id propChanId = [config objectForKey:@"PropagationChannelId"];
    if (![propChanId isKindOfClass:[NSString class]]) {
        [PsiFeedbackLogger errorWithType:AppInfoLogType format:@"PropagationChannelId invalid type %@", NSStringFromClass([propChanId class])];
    }

    return (NSString*)propChanId;
}

+ (NSString*)sponsorId {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:PsiphonAppGroupIdentifier];
    return [sharedDB getCurrentSponsorId];
}

// Code is borrowed from: https://github.com/Psiphon-Labs/psiphon-tunnel-core/blob/master/MobileLibrary/iOS/PsiphonTunnel/PsiphonTunnel/PsiphonTunnel.m
+ (NSString *)clientPlatform {
    // ClientPlatform must not contain:
    //   - underscores, which are used by us to separate the constituent parts
    //   - spaces, which are considered invalid by the server
    // Like "iOS". Older iOS reports "iPhone OS", which we will convert.
    NSString *systemName = [[UIDevice currentDevice] systemName];
    
    if ([systemName isEqual: @"iPhone OS"]) {
        systemName = @"iOS";
    }
    systemName = [[systemName
                   stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
                  stringByReplacingOccurrencesOfString:@" " withString:@"-"];
    
    // Like "10.2.1"
    NSString *systemVersion = [[[[UIDevice currentDevice]systemVersion]
                                stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
                               stringByReplacingOccurrencesOfString:@" " withString:@"-"];

    // The value of this property is YES only when the process is an iOS app running on a Mac.
    // The value of the property is NO for all other apps on the Mac, including Mac apps built
    // using Mac Catalyst. The property is also NO for processes running on platforms other than macOS.
    BOOL isiOSAppOnMac = FALSE;
    if (@available(iOS 14.0, *)) {
         isiOSAppOnMac = [[NSProcessInfo processInfo] isiOSAppOnMac];
    }
    
    // The value of this property is true when the process is:
    // - A Mac app built with Mac Catalyst, or an iOS app running on Apple silicon.
    // - Running on a Mac.
    BOOL isMacCatalystApp = FALSE;
    if (@available(iOS 14.0, *)) {
        isMacCatalystApp = [[NSProcessInfo processInfo] isMacCatalystApp];
    }
    
    // "unjailbroken"/"jailbroken/iOSAppOnMac/MacCatalystApp"
    NSString *detail = @"unjailbroken";
    
    if (isiOSAppOnMac == TRUE && isMacCatalystApp == TRUE) {
        detail = @"iOSAppOnMac";
    } else if (isiOSAppOnMac == FALSE && isMacCatalystApp == TRUE) {
        detail = @"MacCatalystApp";
    } else {
        // App is an iOS app running on iOS.
        if ([JailbreakCheck isDeviceJailbroken]) {
            detail = @"jailbroken";
        }
    }
    
    // Like "com.psiphon3.browser"
    NSString *bundleIdentifier = [[[[NSBundle mainBundle] bundleIdentifier]
                                   stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
                                  stringByReplacingOccurrencesOfString:@" " withString:@"-"];

    NSString *clientPlatform = [NSString stringWithFormat:@"%@_%@_%@_%@",
                                systemName,
                                systemVersion,
                                detail,
                                bundleIdentifier];
    
    return clientPlatform;
}

+ (BOOL)runningUITest {
#if DEBUG
    static BOOL runningUITest;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if ([[NSUserDefaults standardUserDefaults] boolForKey:AppInfoFastLaneSnapShotBoolKey]) {
            NSDictionary *environmentDictionary = [[NSProcessInfo processInfo] environment];

            if ([environmentDictionary[@"PsiphonUITestEnvironment.runningUITest"] isEqualToString:@"1"]) {
                runningUITest = TRUE;
            }

            if ([environmentDictionary[@"PsiphonUITestEnvironment.disableAnimations"] isEqualToString:@"1"]) {
                [UIView setAnimationsEnabled:FALSE];
            }
        }
    });
    return runningUITest;
#else
    return FALSE;
#endif
}

@end
