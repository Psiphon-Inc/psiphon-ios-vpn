/*
 * Copyright (c) 2020, Psiphon Inc.
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

#import "ExtensionDataStore.h"
#import "ExtensionDataStoreKeys.h"
#import "SharedConstants.h"

@interface ExtensionDataStore ()

@property (strong, nonatomic) id<KeyedDataStore>dataStore;

@end

@implementation ExtensionDataStore

+ (instancetype)standard {
    id<KeyedDataStore> keyedDataStore = (id<KeyedDataStore>)[[NSUserDefaults alloc] initWithSuiteName:PsiphonAppGroupIdentifier];
    ExtensionDataStore *obj = [[ExtensionDataStore alloc] initWithDataStore:keyedDataStore];
    return obj;
}

- (instancetype)initWithDataStore:(id<KeyedDataStore>)dataStore {
    self = [super init];
    if (self) {
        self.dataStore = dataStore;
    }
    return self;
}

#pragma mark - Jetsam data

- (NSDate*)extensionStartTime {
    return [self.dataStore lookup:ExtensionStartTimeKey];
}

- (void)setExtensionStartTimeToNow {
    [self.dataStore insert:[NSDate date] key:ExtensionStartTimeKey];
}

- (NSDate*)tickerTime {
    return [self.dataStore lookup:TickerTimeKey];
}

- (void)setTickerTimeToNow {
    [self.dataStore insert:[NSDate date] key:TickerTimeKey];
}

@end
