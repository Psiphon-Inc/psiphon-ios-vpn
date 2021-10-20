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
#import <PsiphonTunnel/PsiphonClientPlatform.h>

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
    NSDictionary *config = [PsiphonConfigReader load].config;
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

+ (NSString *)clientPlatform {
    return [PsiphonClientPlatform getClientPlatform];
}

+ (BOOL)isiOSAppOnMac {
    
    BOOL isiOSAppOnMac = FALSE;
    
    if (@available(iOS 14.0, *)) {
        if ([[NSProcessInfo processInfo] isiOSAppOnMac] == TRUE) {
            isiOSAppOnMac = TRUE;
        }
    }
    
    return isiOSAppOnMac;
    
}

+ (BOOL)isOperatingSystemAtLeastVersion15 {
    NSOperatingSystemVersion ios15 = {.majorVersion = 15, .minorVersion = 0, .patchVersion = 0};
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios15];
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
