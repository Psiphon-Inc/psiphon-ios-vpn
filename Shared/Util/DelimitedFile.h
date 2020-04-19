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

FOUNDATION_EXPORT NSErrorDomain const DelimitedFileErrorDomain;

typedef NS_ERROR_ENUM(DelimitedFileErrorDomain, DelimitedFileErrorCode) {
    DelimitedFileErrorFileDoesNotExist = 1,
    DelimitedFileErrorGetFileHandleFailed = 2,
    DelimitedFileErrorReadFailed = 3,
    DelimitedFileErrorDecodingFailed = 4,
};

/// DelimitedFile facilitates reading an ASCII encoded file with newline delimiters line-by-line.
@interface DelimitedFile : NSObject <NSStreamDelegate>

@property (readonly, strong, nonatomic) NSFileHandle *fileHandle;

/// Number of bytes read from the file.
/// @warning Bytes may remain in the internal buffer. Use `bytesReturned` to track the number of bytes returned.
@property (readonly, nonatomic) NSUInteger bytesRead;
/// Number of bytes that have been processed to return the last line returned from `readLineWithError:`. This number should be used
/// to resume reading lines in the future.
@property (readonly, nonatomic) NSUInteger bytesReturned;

- (instancetype)init NS_UNAVAILABLE;

/// Init the reader.
/// @param filepath Location of the file to be read.
/// @param chunkSize Number of bytes to read from the file at a time.
/// @param outError If non-nill on return, then initialization failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
- (nullable instancetype)initWithFilepath:(NSString*)filepath
                                chunkSize:(NSUInteger)chunkSize
                                    error:(NSError * _Nullable *)outError NS_DESIGNATED_INITIALIZER;

/// Read a line from the file.
/// @param outError If non-nill on return, then reading data failed with the provided error.
/// @return Returns nil when all lines have been read or `outError` is non-nil.
- (NSString*)readLineWithError:(NSError * _Nullable *)outError;

@end

NS_ASSUME_NONNULL_END
