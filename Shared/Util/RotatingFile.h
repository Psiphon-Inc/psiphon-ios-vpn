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

FOUNDATION_EXPORT NSErrorDomain const RotatingFileErrorDomain;

/// Represents a log file which is rotated once it exceeds a configurable maximum size.
@interface RotatingFile : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initialize a rotating notice file.
/// @param filepath Path of file which will be written.
/// @param olderFilepath Path where `filepath` will be moved once it exceeds `maxFileSizeBytes`.
/// @param maxFileSizeBytes Maximum number of bytes that will be stored in the rotated file.
/// @param outError If non-nill on return, then initialization failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
- (nullable instancetype)initWithFilepath:(NSString *)filepath
                            olderFilepath:(NSString *)olderFilepath
                         maxFilesizeBytes:(unsigned long long)maxFileSizeBytes
                                    error:(NSError * _Nullable *)outError NS_DESIGNATED_INITIALIZER;

/// Write the rotating notice file.
/// If the filesize has exceeded the configured maximum file size (see `maxFileSizeBytes`),
/// then the file will first be rotated (to `olderFilepath`) and then a new file will be created with
/// the provided data (at `filepath`).
/// @param data Data to be written.
/// @param outError If non-nill on return, then writing data failed with the provided error.
- (void)writeData:(NSData *)data error:(NSError * _Nullable *)outError;

@end

NS_ASSUME_NONNULL_END
