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

/// Represents the state of a file in the filesystem from the perspective of a reader.
/// This allows the reader to only read new data when the file is appended to.
@interface FileRegistryEntry : NSObject <NSCoding, NSSecureCoding>

@property (readonly, nonatomic) NSString *filepath;
@property (readonly, nonatomic, assign) unsigned long long fileSystemFileNumber;
@property (nonatomic, assign) unsigned long long offset;

+ (FileRegistryEntry*)fileRegistryEntryWithFilepath:(NSString*)filePath
                               fileSystemFileNumber:(unsigned long long)fileSystemFileNumber
                                             offset:(unsigned long long)offset;

- (BOOL)isEqualToFileRegistryEntry:(FileRegistryEntry*)fileRegistryEntry;

@end

/// Represents the state of a group of files in the filesystem from the perspective of a reader.
/// This allows the reader to only read new data when a file is appended to.
@interface FileRegistry : NSObject <NSCoding, NSSecureCoding>

@property (readonly, nonatomic, strong) NSDictionary<NSString*, FileRegistryEntry*>* entries;

/// Adds an entry to the registry with the filepath as the key. Will overwrite previous entries with the same key.
/// @param entry Entry to add to the registry.
- (void)setEntry:(FileRegistryEntry*)entry;

/// Get an entry from the registry.
/// @param filepath Filepath to find an entry for.
/// @returns The entry if one exists for the given filepath. Otherwise returns nil.
- (FileRegistryEntry*_Nullable)entryForFilepath:(NSString*)filepath;

/// Removes an entry from the registry.
/// @param filepath Key to delete from the registry.
- (void)removeEntryForFilepath:(NSString*)filepath;

- (BOOL)isEqualToFileRegistry:(FileRegistry*)fileRegistry;

@end

NS_ASSUME_NONNULL_END
