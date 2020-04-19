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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ArchiverErrorDomain;

typedef NS_ERROR_ENUM(ArchiverErrorDomain, ArchiverFileErrorCode) {
    ArchiverErrorArchiveFailed = 1,
    ArchiverErrorUnarchiveFailed = 2
};

/// Convenience class for archiving and unarchiving data.
@interface Archiver : NSObject

/// Archives the given object with a keyed archiver.
/// @param object Object to archive.
/// @param outError If non-nill on return, then initialization failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
+ (nullable NSData *)archiveObject:(id<NSCoding, NSSecureCoding>)object
                             error:(NSError * _Nullable *)outError;

/// Unarchives the given object with a keyed archiver.
/// @param data Data which represents a keyed archive.
/// @param outError If non-nill on return, then initialization failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
+ (nullable id)unarchiveObjectWithData:(NSData*)data
                                 error:(NSError * _Nullable *)outError;

@end

NS_ASSUME_NONNULL_END
