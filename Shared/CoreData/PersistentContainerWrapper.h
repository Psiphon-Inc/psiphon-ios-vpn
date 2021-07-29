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

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const PersistentContainerWrapperErrorDomain;

typedef NS_ERROR_ENUM(PersistentContainerWrapperErrorDomain, PersistentContainerErrorCode) {
    // Failed to get the URL to the persistent container store file.
    PersistentContainerErrorCodeAppGroupContainerURLFailed = -1
};

@interface PersistentContainerWrapper : NSObject

/**
 NSPersistentContainer's viewContext property is configured as a NSMainQueueConcurrencyType context.
 
 perform(_:) and performAndWait(_:) ensure the block operations execute on the correct queue for the context.
 */
@property (nonatomic, readonly, nonnull) NSPersistentContainer *container;

/**
 Typical reasons for an error here include:
 - The parent directory does not exist, cannot be created, or disallows writing.
 - The persistent store is not accessible, due to permissions or data protection when the device is locked.
 - The device is out of space.
 - The store could not be migrated to the current model version.
 Check the error message to determine what the actual problem was.
 */
+ (PersistentContainerWrapper *_Nullable)load:(NSError *_Nullable *_Nonnull)error;

@end

NS_ASSUME_NONNULL_END
