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
                [AppUpgrade handleAppUpgradeFromVersion:lastLaunchAppVersion];
            }
        }
    });
    return firstRunOfVersion;
}

// For safety and simplicity, only `oldVersionString` is provided here.
// Should not rely on the current build number, as that build number is not specified yet.
+ (void)handleAppUpgradeFromVersion:(NSString *)oldVersionString {

    assert(oldVersionString != nil);
    NSInteger oldVersion = [oldVersionString integerValue];

    // Remove legacy privacy-policy related keys
    if (oldVersion <= 106) {
        ContainerDB *containerDB = [[ContainerDB alloc] init];

        NSUserDefaults *containerDBUserDefaults = NSUserDefaults.standardUserDefaults;
        NSArray<NSString *> *keysSnapshot = [[containerDBUserDefaults dictionaryRepresentation] allKeys];

        NSString *pre100LegacyKey = @"PrivacyPolicy.AcceptedBoolKey";
        NSString *legacyPPAcceptedKey = @"ContainerDB.PrivacyPolicyAcceptedRFC3339StringKey";

        if ([keysSnapshot containsObject:pre100LegacyKey] ||
            [keysSnapshot containsObject:legacyPPAcceptedKey]) {

            [containerDBUserDefaults removeObjectForKey:pre100LegacyKey];
            [containerDBUserDefaults removeObjectForKey:legacyPPAcceptedKey];

            // Assume that the user has finished onboarding.
            [containerDB setHasFinishedOnboarding];

            // If these keys have non-nil value, then the user has accepted the
            // privacy policy version 2018-05-15T19:39:57+00:00.
            [containerDB setAcceptedPrivacyPolicy:@"2018-05-15T19:39:57+00:00"];
        }

    }

    // TODO: on new PsiCash release delete the key defined:
    // UserDefaultsKey const PsiCashHasBeenOnboardedBoolKey = @"PsiCash.HasBeenOnboarded";

}

@end
