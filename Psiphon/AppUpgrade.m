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

#import "AppUpgrade.h"
#import "ContainerDB.h"
#import "Asserts.h"
#import "AppInfo.h"
#import "NSDate+PSIDateExtension.h"


PsiFeedbackLogType const AppUpgradeLogType = @"AppUpgrade";

@implementation AppUpgrade

+ (BOOL)firstRunOfAppVersion {
    static BOOL firstRunOfVersion;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ContainerDB *containerDB = [[ContainerDB alloc] init];

        NSString *appVersion = [AppInfo appVersion];
        PSIAssert(appVersion != nil);
        NSString *_Nullable lastLaunchAppVersion = [containerDB storedAppVersion];

        if ([appVersion isEqualToString:lastLaunchAppVersion]) {
            firstRunOfVersion = FALSE;
        } else {
            firstRunOfVersion = TRUE;

            NSMutableDictionary *versions = [[NSMutableDictionary alloc] init];
            if (lastLaunchAppVersion) {
                versions[@"old"] = lastLaunchAppVersion;
            }
            if (appVersion) {
                versions[@"new"] = appVersion;
                [containerDB storeCurrentAppVersion:appVersion];
            }

            [PsiFeedbackLogger infoWithType:AppUpgradeLogType json:@{@"CFBundleVersion":versions}];

            // Handle app upgrade.
            if (lastLaunchAppVersion) {
                [AppUpgrade handleAppUpgradeFromVersion:lastLaunchAppVersion toVersion:appVersion];
            }
        }
    });
    return firstRunOfVersion;
}

+ (void)handleAppUpgradeFromVersion:(NSString *)oldVersionString
                          toVersion:(NSString *)newVersionString {

    assert(oldVersionString != nil);
    assert(newVersionString != nil);

    NSInteger oldVersion = [oldVersionString integerValue];
    NSInteger newVersion = [newVersionString integerValue];

    ContainerDB *containerDB = [[ContainerDB alloc] init];

    // Upgrade from 98 and below to 99 and above:
    // - Privacy policy has changed from stored bool value, to storing privacy policy update date.
    if (oldVersion <= 98 && newVersion >= 99) {

        // Privacy policy that that would have been accepted by versions 98 and below.
        NSNumber *pre99PrivacyPolicyTime = [NSNumber numberWithLongLong:1526413197];
        NSString *pre99LegacyKey = @"PrivacyPolicy.AcceptedBoolKey";

        // Check if the legacy keys exist first.
        NSNumber *_Nullable pre99PrivacyPolicyAccepted = [NSUserDefaults.standardUserDefaults
          objectForKey:pre99LegacyKey];

        if (pre99PrivacyPolicyAccepted) {
            if ([pre99PrivacyPolicyAccepted boolValue]) {
                [containerDB setAcceptedPrivacyPolicyUnixTime:pre99PrivacyPolicyTime];
            }

            // Remove old key.
            [NSUserDefaults.standardUserDefaults removeObjectForKey:pre99LegacyKey];
        }
    }

    // Upgrade from 105 to 106 and above:
    // - In 105 Privacy policy dates were stored as NSDates, which caused numerical imprecision when parsed
    //   using `[NSDate dateWithTimeIntervalSince1970:]` methods.
    // - In 106 we move towards storing privacy policy update dates as Unix timestamps.
    // - Convert stored RFC3339 format in build 105 to the new format only if it is not nil.
    if (oldVersion == 105 && newVersion >= 106) {

        NSNumber *pre106PrivacyPolicyTime = [NSNumber numberWithLongLong:1526413197];
        NSString *ppKey = @"ContainerDB.PrivacyPolicyAcceptedRFC3339StringKey";
        id _Nullable lastAcceptedPP = [NSUserDefaults.standardUserDefaults objectForKey:ppKey];

        // Don't do anything if `lastAcceptedPP` doesn't have any stored value.
        if (!lastAcceptedPP) {
            return;
        }

        // Overwrite current value if `lastAcceptedPP` is set, since if `lastAcceptedPP` is not nil,
        // it must the same as `pre106PrivacyPolicyTime` in RFC3339 format.
        [containerDB setAcceptedPrivacyPolicyUnixTime:pre106PrivacyPolicyTime];
    }

}

@end
