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

#import "AppInfo.h"
#import "Asserts.h"
#import "PsiphonConfigReader.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "UserDefaults.h"

PsiFeedbackLogType const AppInfoLogType = @"AppInfo";

UserDefaultsKey const AppInfoFastLaneSnapShotBoolKey = @"FASTLANE_SNAPSHOT";

@implementation AppInfo

+ (NSString*)appVersion {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}

#if !(TARGET_IS_EXTENSION)

+ (NSString*)clientRegion {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    return [sharedDB emittedClientRegion];
}

+ (NSString*)propagationChannelId {
    NSDictionary *configs = [PsiphonConfigReader fromConfigFile].configs;
    if (!configs) {
        // PsiphonConfigReader has logged an error
        return nil;
    }
    id propChanId = [configs objectForKey:@"PropagationChannelId"];
    if (![propChanId isKindOfClass:[NSString class]]) {
        [PsiFeedbackLogger errorWithType:AppInfoLogType message:@"PropagationChannelId invalid type %@", NSStringFromClass([propChanId class])];
    }

    return (NSString*)propChanId;
}

+ (NSString*)sponsorId {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    return [sharedDB getCurrentSponsorId];
}

#endif

+ (BOOL)runningUITest {
#if DEBUG
    static BOOL runningUITest;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if ([[NSUserDefaults standardUserDefaults] boolForKey:AppInfoFastLaneSnapShotBoolKey]) {
            NSDictionary *environmentDictionary = [[NSProcessInfo processInfo] environment];
            if (environmentDictionary[@"PsiphonUITestEnvironment"] != nil) {
                runningUITest = TRUE;
            }
        }
    });
    return runningUITest;
#else
    return FALSE;
#endif
}

@end
