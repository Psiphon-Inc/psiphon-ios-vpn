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

#import "ContainerDB.h"
#import "NSDate+PSIDateExtension.h"
#import "UserDefaults.h"
#import "Logging.h"

#pragma mark - NSUserDefaultsKey

UserDefaultsKey const EmbeddedEgressRegionsStringArrayKey =
    @"embedded_server_entries_egress_regions";  // legacy key

UserDefaultsKey const AppInfoLastCFBundleVersionStringKey = @"LastCFBundleVersion"; // legacy key

UserDefaultsKey const FinishedOnboardingBoolKey = @"ContainerDB.FinishedOnboardingBoolKey";

UserDefaultsKey const PrivacyPolicyAcceptedStringTimeKey = @"ContainerDB.PrivacyPolicyAcceptedStringTimeKey2";

#pragma mark -

@implementation ContainerDB

- (NSString *_Nullable)storedAppVersion {
    return [NSUserDefaults.standardUserDefaults stringForKey:AppInfoLastCFBundleVersionStringKey];
}

- (void)storeCurrentAppVersion:(NSString *)appVersion {
    [NSUserDefaults.standardUserDefaults setObject:appVersion
                                            forKey:AppInfoLastCFBundleVersionStringKey];
}

#pragma mark -

- (BOOL)hasFinishedOnboarding {
    return [NSUserDefaults.standardUserDefaults boolForKey:FinishedOnboardingBoolKey];
}

- (void)setHasFinishedOnboarding {
    [NSUserDefaults.standardUserDefaults setBool:TRUE forKey:FinishedOnboardingBoolKey];
}

#pragma mark -

- (NSString *)privacyPolicyLastUpdateTime {
    return @"2018-05-15T19:39:57+00:00";
}

- (NSString *_Nullable)lastAcceptedPrivacyPolicy {
    NSString *_Nullable unixTime = [NSUserDefaults.standardUserDefaults
      stringForKey:PrivacyPolicyAcceptedStringTimeKey];

    return unixTime;
}

- (BOOL)hasAcceptedLatestPrivacyPolicy {
    NSString *_Nullable lastAccepted = [self lastAcceptedPrivacyPolicy];
    return [[self privacyPolicyLastUpdateTime] isEqualToString:lastAccepted];
}

- (void)setAcceptedPrivacyPolicy:(NSString *)privacyPolicyTimestamp {
    [NSUserDefaults.standardUserDefaults setObject:privacyPolicyTimestamp
                                            forKey:PrivacyPolicyAcceptedStringTimeKey];
}

- (void)setAcceptedLatestPrivacyPolicy {
    [NSUserDefaults.standardUserDefaults setObject:[self privacyPolicyLastUpdateTime]
                                            forKey:PrivacyPolicyAcceptedStringTimeKey];
}

#pragma mark -

- (void)setEmbeddedEgressRegions:(NSArray<NSString *> *_Nullable)regions {
    [NSUserDefaults.standardUserDefaults setObject:regions
                                            forKey:EmbeddedEgressRegionsStringArrayKey];
}

- (NSArray<NSString *> *)embeddedEgressRegions {
    return [NSUserDefaults.standardUserDefaults objectForKey:EmbeddedEgressRegionsStringArrayKey];
}

@end
