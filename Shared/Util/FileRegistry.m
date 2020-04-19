//
//  FileRegistry.m
//  Psiphon
//
//  Created by user on 2020-05-01.
//  Copyright © 2020 Psiphon Inc. All rights reserved.
//

#import "FileRegistry.h"

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const FileRegistryEntryArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const FileRegistryEntryArchiveVersionIntegerCoderKey = @"version.integer";
NSString *_Nonnull const FileRegistryEntryFilePathStringCoderKey = @"filepath.string";
NSString *_Nonnull const FileRegistryEntryFileSystemFileNoIntCoderKey = @"file_system_file_no.int";
NSString *_Nonnull const FileRegistryEntryOffsetIntCoderKey = @"offset.int";

@interface FileRegistryEntry ()

@property (nonatomic, assign) NSString *filepath;
@property (nonatomic, assign) unsigned long long fileSystemFileNumber;
@property (nonatomic, assign) unsigned long long offset;

@end

@implementation FileRegistryEntry

+ (FileRegistryEntry*)fileRegistryEntryWithFilepath:(NSString*)filepath
                               fileSystemFileNumber:(unsigned long long)fileSystemFileNumber
                                             offset:(unsigned long long)offset {

    FileRegistryEntry *entry = [[FileRegistryEntry alloc] init];
    if (entry) {
        entry.filepath = filepath;
        entry.fileSystemFileNumber = fileSystemFileNumber;
        entry.offset = offset;
    }

    return entry;
}

#pragma mark - Equality

- (BOOL)isEqualToFileRegistryEntry:(FileRegistryEntry*)fileRegistryEntry {
    return
      [self.filepath isEqualToString:fileRegistryEntry.filepath] &&
      self.fileSystemFileNumber == fileRegistryEntry.fileSystemFileNumber &&
      self.offset == fileRegistryEntry.offset;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[FileRegistryEntry class]]) {
        return NO;
    }

    return [self isEqualToFileRegistryEntry:(FileRegistryEntry*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInteger:FileRegistryEntryArchiveVersion1
                  forKey:FileRegistryEntryArchiveVersionIntegerCoderKey];
    [coder encodeObject:self.filepath
                 forKey:FileRegistryEntryFilePathStringCoderKey];
    [coder encodeInt:(int)self.fileSystemFileNumber
              forKey:FileRegistryEntryFileSystemFileNoIntCoderKey];
    [coder encodeInt:(int)self.offset
              forKey:FileRegistryEntryOffsetIntCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.filepath = [coder decodeObjectOfClass:[NSString class]
                                            forKey:FileRegistryEntryFilePathStringCoderKey];
        self.fileSystemFileNumber = [coder decodeIntForKey:FileRegistryEntryFileSystemFileNoIntCoderKey];
        self.offset = [coder decodeIntForKey:FileRegistryEntryOffsetIntCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementatino

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const FileRegistryArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const FileRegistryArchiveVersionIntegerCoderKey = @"version.integer";
NSString *_Nonnull const FileRegistryEntriesDictCoderKey = @"entries.dict";

@interface FileRegistry ()

@property (nonatomic, strong) NSDictionary<NSString*, FileRegistryEntry*>* entries;

@end

@implementation FileRegistry

- (void)setEntry:(FileRegistryEntry*)entry {
    @synchronized (self) {
        NSMutableDictionary *newEntries = [NSMutableDictionary dictionaryWithDictionary:self.entries];
        [newEntries setObject:entry forKey:entry.filepath];
        self.entries = newEntries;
    }
}

- (void)removeEntryForFilepath:(NSString*)filepath {
    @synchronized (self) {
        NSMutableDictionary *newEntries = [NSMutableDictionary dictionaryWithDictionary:self.entries];
        [newEntries removeObjectForKey:filepath];
        self.entries = newEntries;
    }
}

#pragma mark - Equality

- (BOOL)isEqualToFileRegistry:(FileRegistry*)fileRegistry {
    return [self.entries isEqualToDictionary:fileRegistry.entries];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[FileRegistry class]]) {
        return NO;
    }

    return [self isEqualToFileRegistry:(FileRegistry*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInteger:FileRegistryEntryArchiveVersion1
                  forKey:FileRegistryArchiveVersionIntegerCoderKey];
    [coder encodeObject:self.entries
                 forKey:FileRegistryEntriesDictCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.entries = [coder decodeObjectOfClass:[NSDictionary class]
                                           forKey:FileRegistryEntriesDictCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementatino

+ (BOOL)supportsSecureCoding {
   return YES;
}

@end
