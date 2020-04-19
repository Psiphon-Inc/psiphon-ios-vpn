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

#import "PersistentSubsMetadata.h"
#import "LocalDataStoreKeys.h"
#import "NSUserDefaults+KeyedDataStore.h"

@implementation PersistentSubsMetadataUserDefaults

+ (id<KeyedDataStore>)defaultDataStore {
    return [NSUserDefaults standardUserDefaults];
}

+ (NSString*)lastAuthID {
    return [PersistentSubsMetadata lastAuthID:PersistentSubsMetadataUserDefaults.defaultDataStore];
}

+ (void)setLastAuthID:(NSString*)lastAuthID {
    [PersistentSubsMetadata setLastAuthID:PersistentSubsMetadataUserDefaults.defaultDataStore
                     lastAuthID:lastAuthID];
}

+ (NSString*)lastAuthAccessType {
    return [PersistentSubsMetadata lastAuthAccessType:PersistentSubsMetadataUserDefaults.defaultDataStore];
}

+ (void)setLastAuthAccessType:(NSString*)lastAuthAccessType {
    [PersistentSubsMetadata setLastAuthAccessType:PersistentSubsMetadataUserDefaults.defaultDataStore
                         lastAccessType:lastAuthAccessType];
}

@end

@implementation PersistentSubsMetadata

+ (NSString*)lastAuthID:(id<KeyedDataStore>)dataStore {
    return [dataStore lookup:LastAuthIDKey];
}

+ (void)setLastAuthID:(id<KeyedDataStore>)dataStore
           lastAuthID:(NSString*)lastAuthID {

    [dataStore insert:lastAuthID key:LastAuthIDKey];
}

+ (NSString*)lastAuthAccessType:(id<KeyedDataStore>)dataStore {
    return [dataStore lookup:LastAuthAccessTypeKey];
}

+ (void)setLastAuthAccessType:(id<KeyedDataStore>)dataStore
               lastAccessType:(NSString*)lastAuthAccessType {

    [dataStore insert:lastAuthAccessType key:LastAuthAccessTypeKey];
}

@end
