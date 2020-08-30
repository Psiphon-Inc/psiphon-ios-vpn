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

@interface ExtensionDataStore ()

@property (strong, nonatomic) id<KeyedDataStore>dataStore;

@end

@implementation ExtensionDataStore

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

#pragma mark - Alerts

- (NSSet<NSNumber *> *_Nonnull)getSessionAlerts {
    NSSet *_Nullable set = [NSSet setWithArray:[self.dataStore lookup:SessionAlertsKey]];
    if (set == nil) {
        return [NSSet set];
    } else {
        return set;
    }
}

- (BOOL)addSessionAlert:(NSNumber *)alertId {
    NSMutableSet *_Nonnull set = [NSMutableSet setWithSet:[self getSessionAlerts]];
    if ([set containsObject:alertId] == TRUE) {
        return FALSE;
    }
    [set addObject:alertId];
    [self.dataStore insert:[set allObjects] key:SessionAlertsKey];
    return TRUE;
}

- (void)removeSessionAlert:(NSNumber *)alertId {
    NSMutableSet *_Nonnull set = [NSMutableSet setWithSet:[self getSessionAlerts]];
    [set removeObject:alertId];
    [self.dataStore insert:[set allObjects] key:SessionAlertsKey];
}

- (void)removeAllSessionAlerts {
    [self.dataStore removeObjectForKey:SessionAlertsKey];
}

@end
