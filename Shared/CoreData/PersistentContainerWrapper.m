/*
 * Copyright (c) 2021, Psiphon Inc.
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

#import "PersistentContainerWrapper.h"
#import "AppFiles.h"

NSErrorDomain _Nonnull const PersistentContainerWrapperErrorDomain = @"PersistentContainerWrapper";



@interface PersistentContainerWrapper ()

@property (nonatomic, readwrite, nonnull) NSPersistentContainer *container;

@end

@implementation PersistentContainerWrapper

+ (PersistentContainerWrapper *_Nullable)load:(NSError *_Nullable *_Nonnull)error {
    
    PersistentContainerWrapper *instance = [[PersistentContainerWrapper alloc] init];
    instance.container = [[NSPersistentContainer alloc] initWithName:@"SharedModel"];
    
    // Sets database type as SQLite, and downgrades file protection level from
    // the default NSFileProtectionCompleteUntilFirstUserAuthentication to
    // NSFileProtectionNone.
    // This is necessary so that the database files can be accessed by the Network Extension
    // when it is started before the user has unlocked their device.
    NSPersistentStoreDescription *storeDescription = [[NSPersistentStoreDescription alloc]
                                                      initWithURL:[AppFiles sharedSqliteDB]];
    [storeDescription setType:NSSQLiteStoreType];
    [storeDescription setOption:NSFileProtectionNone forKey:NSPersistentStoreFileProtectionKey];
    [storeDescription setShouldAddStoreAsynchronously:FALSE]; // Made default value explicit.

    instance.container.persistentStoreDescriptions = @[storeDescription];
    
    NSURL *_Nullable storeURL = [AppFiles sharedSqliteDB];
    
    if (storeURL == nil) {
        *error = [NSError errorWithDomain:PersistentContainerWrapperErrorDomain
                                     code:PersistentContainerErrorCodeAppGroupContainerURLFailed
                                 userInfo:nil];
        return nil;
    }
    
    __block NSError *e = nil;
    
    
    // Once the completion handler has fired, the Core Data stack is fully initialized
    // and is ready for use.
    // This call is synchronous since shouldAddStoreAsynchronously is FALSE by default.
    [instance.container loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription * _Nonnull storeDescription, NSError * _Nullable error) {
        
        e = error;
        
    }];
    
    if (e != nil) {
        *error = e;
        return nil;
    } else {
        *error = nil;
        return instance;
    }
    
}

@end
