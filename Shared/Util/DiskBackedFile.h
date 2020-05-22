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

FOUNDATION_EXPORT NSErrorDomain const DiskBackedFileErrorDomain;

typedef NS_ERROR_ENUM(DiskBackedFileErrorDomain, DiskBackedFileErrorCode) {
    DiskBackedFileErrorFileDoesNotExist = 1,
    DiskBackedFileErrorGetFileHandleFailed = 2,
    DiskBackedFileErrorGetAttributesFailed = 3,
    DiskBackedFileErrorReadFailed = 4,
    DiskBackedFileErrorWriteFailed = 5,
    DiskBackedFileErrorCreateFileFailed = 6,
    DiskBackedFileErrorDeleteFileFailed = 7,
    DiskBackedFileErrorSyncFileFailed = 8
};

/// Convenience class for interacting with the filesystem.
@interface DiskBackedFile : NSObject

/// Check whether a file exists at a given path in the filesystem.
/// @param filepath Path of the file.
/// @return True if a file exists at the given path, otherwise false.
+ (BOOL)fileExistsAtPath:(NSString*)filepath;

/// Return the data contained within the file at the specified path.
/// @param filepath Path of the file that should be read from.
/// @param outError If non-nill on return, then writing data failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
+ (NSData *_Nullable)fileDataAtPath:(NSString*)filepath error:(NSError * _Nullable *)outError;

/// Create file with given data.
/// @param filepath Filepath to write to. If a file exists at this path, it will be overwritten.
/// @param data Data to write.
/// @param outError If non-nill on return, then writing data failed with the provided error.
+ (void)createFileAtPath:(NSString*)filepath
                    data:(NSData*)data
                   error:(NSError * _Nullable *)outError;

/// Append data to file.
/// @param filepath Filepath of file to append to.
/// @param data Data to append.
/// @param outError If non-nill on return, then writing data failed with the provided error.
+ (void)appendDataToFileAtPath:(NSString*)filepath
                          data:(NSData*)data
                         error:(NSError * _Nullable *)outError;

/// Write data to file.
/// @param filepath Filepath of file to write to.
/// @param data Data to write.
/// @param outError If non-nill on return, then writing data failed with the provided error.
+ (void)writeDataToFileAtPath:(NSString*)filepath
                         data:(NSData*)data
                        error:(NSError * _Nullable *)outError;

@end

NS_ASSUME_NONNULL_END
