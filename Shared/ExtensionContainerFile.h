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

/*
 * Two classes which facilitate writing and reading a rotated file from different processes.
 * The reading process tracks the amount of data it has read from both files (tracked by filepath
 * and inode) so it can resume reading in the future.
 */

NS_ASSUME_NONNULL_BEGIN

#if TARGET_IS_CONTAINER || TARGET_IS_TEST

FOUNDATION_EXPORT NSErrorDomain const ContainerReaderRotatedFileErrorDomain;

typedef NS_ERROR_ENUM(ContainerReaderRotatedFileErrorDomain, ContainerReaderRotatedFileErrorCode) {
    ContainerReaderRotatedFileErrorReadRegistryFailed = 1,
    ContainerReaderRotatedFileErrorWriteRegistryFailed = 2,
    ContainerReaderRotatedFileErrorUnarchiveRegistryFailed = 3,
    ContainerReaderRotatedFileErrorArchiveRegistryFailed = 4,
    ContainerReaderRotatedFileErrorReadFileFailed = 5,
    ContainerReaderRotatedFileErrorReadOlderFileFailed = 6,
    ContainerReaderRotatedFileErrorFstatFailed = 7,
    ContainerReaderRotatedFileErrorReadLineFailed = 8
};

/// Container (reading process).
@interface ContainerReaderRotatedFile : NSObject

/// Initialize the reader.
/// @param filepath Location of file.
/// @param olderFilepath Location of rotated file.
/// @param registryFilepath Filepath at which to store the registry file (which is used to track file reads).
/// @param readChunkSize Number of bytes to read at a time.
/// @param outError  If non-nill on return, then initializing the reader failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
- (nullable instancetype)initWithFilepath:(NSString*)filepath
                            olderFilepath:(NSString*)olderFilepath
                         registryFilepath:(NSString*)registryFilepath
                            readChunkSize:(NSUInteger)readChunkSize
                                    error:(NSError * _Nullable *)outError;

/// Read the next line. Lines are read back in the other in which they were written.
/// @param outError If non-nill on return, then reading failed with the provided error.
/// @returns nil if there is no more data to read.
- (NSString*_Nullable)readLineWithError:(NSError * _Nullable *)outError;

/// Persist the registry to disk.
/// @param outError If non-nill on return, then persisting the registry failed with the provided error.
- (void)persistRegistry:(NSError * _Nullable *)outError;

@end

#endif

#if TARGET_IS_EXTENSION || TARGET_IS_TEST

FOUNDATION_EXPORT NSErrorDomain const ExtensionWriterRotatedFileErrorDomain;

typedef NS_ERROR_ENUM(ExtensionWriterRotatedFileErrorDomain, ExtensionWriterRotatedFileErrorCode) {
    ExtensionWriterRotatedFileErrorInitRotatingFileFailed = 1,
    ExtensionWriterRotatedFileErrorWriteRotatingFileFailed = 2,
};

/// Extension (writing process).
@interface ExtensionWriterRotatedFile : NSObject

/// Initialize the writer.
/// @param filepath Filepath where the file should be created or appended to if it already exists.
/// @param olderFilepath Filepath where the file should be rotated when it exceeds the configured max filesize.
/// @param maxFileSizeBytes Configured max filesize.
/// @param outError If non-nill on return, then initializing the writer failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
- (nullable instancetype)initWithFilepath:(NSString*)filepath
                            olderFilepath:(NSString*)olderFilepath
                         maxFilesizeBytes:(NSUInteger)maxFileSizeBytes
                                    error:(NSError * _Nullable *)outError;

/// Write data to the rotated file. The file will be rotated before writing if its size has exceeded the configured max filesize.
/// @param data Data to write.
/// @param outError If non-nill on return, then writing data failed with the provided error.
- (void)writeData:(NSData*)data error:(NSError * _Nullable *)outError;

@end

#endif

NS_ASSUME_NONNULL_END
