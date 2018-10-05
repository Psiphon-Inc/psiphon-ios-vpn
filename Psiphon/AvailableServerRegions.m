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

#import "AvailableServerRegions.h"
#import "AppInfo.h"
#import "PsiphonDataSharedDB.h"
#import "RegionAdapter.h"
#import "SharedConstants.h"

@implementation AvailableServerRegions {
    PsiphonDataSharedDB *sharedDB;
}

- (id)init {
    self = [super init];

    if (self) {
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    }

    return self;
}

- (void)sync {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSString *> *regions = [sharedDB emittedEgressRegions];

        if (regions == nil) {
            regions = [sharedDB embeddedEgressRegions];
        }

#if DEBUG
        if ([AppInfo runningUITest]) {
            // fake the availability of all regions in the UI for automated screenshots
            NSMutableArray *faked_regions = [[NSMutableArray alloc] init];
            for (Region *region in [[RegionAdapter sharedInstance] getRegions]) {
                [faked_regions addObject:region.code];
            }
            regions = faked_regions;
        }
#endif
        [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
    });
}

@end
