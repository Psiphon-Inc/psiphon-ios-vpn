/*
 * Copyright (c) 2017, Psiphon Inc.
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

@interface FileUtils : NSObject

+ (BOOL)downgradeFileProtectionToNone:(NSArray<NSString *> *)paths withExceptions:(NSArray<NSString *> *)exceptions;

+ (NSError *)createDir:(NSURL *)dirURL;

+ (NSString *_Nullable)tryReadingFile:(NSString *_Nonnull)filePath;

/*!
 * If fileHandlePtr points to nil, then a new NSFileHandle for
 * reading filePath is created and fileHandlePtr is set to point to the new object.
 * If fileHandlePtr points to a NSFileHandle, it will be used for reading.
 * Reading operation is retried MAX_RETRIES more times if it fails for any reason,
 * while putting the thread to sleep for an amount of time defined by RETRY_SLEEP_TIME.
 * No errors are thrown if opening the file/reading operations fail.
 * @param filePath Path used to create a NSFileHandle if fileHandlePtr points to nil.
 * @param fileHandlePtr Pointer to existing NSFileHandle or nil.
 * @param bytesOffset The byte offset to seek to before reading.
 * @param readToOffset Populated with the file offset that was read to.
 * @return UTF8 string of read file content.
 */
+ (NSString *_Nullable)tryReadingFile:(NSString *_Nonnull)filePath
                      usingFileHandle:(NSFileHandle *_Nullable __strong *_Nonnull)fileHandlePtr
                       readFromOffset:(unsigned long long)bytesOffset
                         readToOffset:(unsigned long long *_Nullable)readToOffset;

/// Returns human-readable size of given `filePath`.
+ (NSString *_Nullable)getFileSize:(NSString *_Nonnull)filePath;

#if DEBUG

/// Lists all files in the target directory.
/// @param dir Directory to list files from.
/// @param resource Resource name for logging. E.g. "Assets Directory".
/// @param recurse If true, recursively list all files in all subdirectories.
+ (void)listDirectory:(NSString *_Nonnull)dir
             resource:(NSString *_Nonnull)resource
          recursively:(BOOL)recurse;

#endif

@end
