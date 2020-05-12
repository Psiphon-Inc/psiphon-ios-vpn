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

#import "ExtensionContainerFile.h"
#import "Archiver.h"
#import "DelimitedFile.h"
#import "DiskBackedFile.h"
#import "FileRegistry.h"
#import "NSError+Convenience.h"
#import "RotatingFile.h"
#import <sys/stat.h>

#if TARGET_IS_CONTAINER || TARGET_IS_TEST

NSErrorDomain _Nonnull const ContainerReaderRotatedFileErrorDomain = @"ContainerReaderRotatedFileErrorDomain";

@implementation ContainerReaderRotatedFile {
    NSString *filepath;
    NSString *olderFilepath;
    NSString *registryFilepath;
    FileRegistry *registry;
    NSUInteger fileInitialOffset;
    NSUInteger olderFileInitialOffset;

    DelimitedFile *file;
    DelimitedFile *olderFile;
}

- (instancetype)initWithFilepath:(NSString*)filepath
                   olderFilepath:(NSString*)olderFilepath
                registryFilepath:(NSString*)registryFilepath
                   readChunkSize:(NSUInteger)readChunkSize
                           error:(NSError * _Nullable *)outError {
    *outError = nil;

    self = [super init];
    if (self) {
        self->filepath = filepath;
        self->olderFilepath = olderFilepath;
        self->registryFilepath = registryFilepath;

        // Initialize registry

        if ([DiskBackedFile fileExistsAtPath:registryFilepath]) {
            NSError *err;
            NSData *registryData = [DiskBackedFile fileDataAtPath:self->registryFilepath error:&err];
            if (err != nil) {
                *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                                code:ContainerReaderRotatedFileErrorReadRegistryFailed
                                 withUnderlyingError:err];
                return nil;
            }

            if (registryData != nil) {
               NSError *err;
               self->registry = [Archiver unarchiveObjectWithData:registryData error:&err];
               if (err != nil) {
                   *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                                   code:ContainerReaderRotatedFileErrorUnarchiveRegistryFailed
                                    withUnderlyingError:err];
                   return nil;
               }
            }
        } else {
            self->registry = [[FileRegistry alloc] init];
        }

        // Open files for reading

        if ([DiskBackedFile fileExistsAtPath:self->filepath]) {
            NSError *err;
            self->file = [[DelimitedFile alloc] initWithFilepath:filepath
                                                       chunkSize:readChunkSize
                                                           error:&err];
            if (err != nil) {
                *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                                code:ContainerReaderRotatedFileErrorReadFileFailed
                                 withUnderlyingError:err];
                return nil;
            }
        }

        if ([DiskBackedFile fileExistsAtPath:self->olderFilepath]) {
            NSError *err;
            self->olderFile = [[DelimitedFile alloc] initWithFilepath:olderFilepath
                                                            chunkSize:readChunkSize
                                                                error:&err];
            if (err != nil) {
                *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                                code:ContainerReaderRotatedFileErrorReadOlderFileFailed
                                 withUnderlyingError:err];
                return nil;
            }
        }

        // Sync registry with current file handle state

        if (olderFile != nil) {

            struct stat older_file_stat;
            int ret = fstat(olderFile.fileHandle.fileDescriptor, &older_file_stat);
            if (ret < 0) {
               *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                               code:ContainerReaderRotatedFileErrorFstatFailed
                            andLocalizedDescription:[NSString stringWithFormat:@"errno(%d): %s", errno, strerror(errno)]];
               return nil;
            }

            FileRegistryEntry *fileEntry = [registry.entries objectForKey:self->filepath];
            FileRegistryEntry *olderFileEntry = [registry.entries objectForKey:self->olderFilepath];

            if (olderFileEntry != nil) {
                if (olderFileEntry.fileSystemFileNumber != older_file_stat.st_ino) {
                    // File was replaced
                    NSUInteger offset = 0;
                    if (fileEntry && fileEntry.fileSystemFileNumber == older_file_stat.st_ino) {
                        // Replacement was the result of a rotation
                        [self->registry removeEntryForFilepath:self->filepath];
                        offset = fileEntry.offset;
                    }

                    olderFileEntry = [FileRegistryEntry fileRegistryEntryWithFilepath:self->olderFilepath
                                                                 fileSystemFileNumber:older_file_stat.st_ino
                                                                               offset:offset];
                }
            } else {
                olderFileEntry = [FileRegistryEntry fileRegistryEntryWithFilepath:self->olderFilepath
                                                             fileSystemFileNumber:older_file_stat.st_ino
                                                                           offset:0];
            }

            [registry setEntry:olderFileEntry];

            if (olderFileEntry.offset >= older_file_stat.st_size) {
                self->olderFile = nil;
            } else {
                [self->olderFile.fileHandle seekToFileOffset:olderFileEntry.offset];
                olderFileInitialOffset = olderFileEntry.offset;
            }
        }

        if (file != nil) {
           struct stat file_stat;
           int ret = fstat(file.fileHandle.fileDescriptor, &file_stat);
           if (ret < 0) {
              *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                              code:ContainerReaderRotatedFileErrorFstatFailed
                           andLocalizedDescription:[NSString stringWithFormat:@"errno(%d): %s", errno, strerror(errno)]];
               return nil;
           }
           FileRegistryEntry *fileEntry = [registry.entries objectForKey:self->filepath];

           if (fileEntry == nil || fileEntry.fileSystemFileNumber != file_stat.st_ino) {
               [registry setEntry:[FileRegistryEntry fileRegistryEntryWithFilepath:self->filepath
                                                              fileSystemFileNumber:file_stat.st_ino
                                                                            offset:0]];
           } else if (fileEntry.offset >= file_stat.st_size) {
               self->file = nil;
           } else {
               [self->file.fileHandle seekToFileOffset:fileEntry.offset];
               fileInitialOffset = fileEntry.offset;
           }
        }
    }

    return self;
}

- (NSString*)readLineWithError:(NSError * _Nullable *)outError {
    *outError = nil;

    NSString *line;

    if (olderFile != nil) {
           NSError *err;
           line = [olderFile readLineWithError:&err];
           if (err != nil) {
               *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                               code:ContainerReaderRotatedFileErrorReadFileFailed
                                withUnderlyingError:err];
               return nil;
           }

           FileRegistryEntry *fileEntry = [registry.entries objectForKey:self->olderFilepath];
           if (fileEntry != nil) {
               FileRegistryEntry *newEntry =
                 [FileRegistryEntry fileRegistryEntryWithFilepath:self->olderFilepath
                                             fileSystemFileNumber:fileEntry.fileSystemFileNumber
                                                           offset:self->olderFileInitialOffset + olderFile.bytesReturned];
               [registry setEntry:newEntry];
           } else {
               *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                               code:ContainerReaderRotatedFileErrorReadRegistryFailed
                            andLocalizedDescription:@"Older file registry not found"];
               return nil;
           }

           if (line != nil) {
               return line;
           } else {
               olderFile = nil;
           }
       }

    if (file != nil) {
        NSError *err;
        line = [file readLineWithError:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                            code:ContainerReaderRotatedFileErrorReadFileFailed
                             withUnderlyingError:err];
            return nil;
        }

        FileRegistryEntry *fileEntry = [registry.entries objectForKey:self->filepath];
        if (fileEntry != nil) {
            FileRegistryEntry *newEntry =
              [FileRegistryEntry fileRegistryEntryWithFilepath:self->filepath
                                          fileSystemFileNumber:fileEntry.fileSystemFileNumber
                                                        offset:self->fileInitialOffset + file.bytesReturned];
            [registry setEntry:newEntry];
        } else {
            *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                            code:ContainerReaderRotatedFileErrorReadRegistryFailed
                         andLocalizedDescription:@"File registry not found"];
            return nil;
        }

        if (line != nil) {
            return line;
        } else {
            file = nil;
        }
    }

    // Done.
    // Both files have been read to completion.
    return nil;
}

- (void)persistRegistry:(NSError * _Nullable *)outError {
    *outError = nil;

    NSError *err;
    NSData *data = [Archiver archiveObject:self->registry error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                        code:ContainerReaderRotatedFileErrorArchiveRegistryFailed
                         withUnderlyingError:err];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self->registryFilepath]) {
        [fm createFileAtPath:self->registryFilepath contents:nil attributes:nil];
    }

    [DiskBackedFile writeDataToFile:data path:self->registryFilepath error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ContainerReaderRotatedFileErrorDomain
                                        code:ContainerReaderRotatedFileErrorWriteRegistryFailed
                         withUnderlyingError:err];
        return;
    }
}

@end

#endif

#if TARGET_IS_EXTENSION || TARGET_IS_TEST

NSErrorDomain _Nonnull const ExtensionWriterRotatedFileErrorDomain = @"ExtensionWriterRotatedFileErrorDomain";

@implementation ExtensionWriterRotatedFile {
    NSString *filepath;
    NSString *olderFilepath;
    RotatingFile *rotatingFile;
}

- (instancetype)initWithFilepath:(NSString*)filepath
                   olderFilepath:(NSString*)olderFilepath
                maxFilesizeBytes:(NSUInteger)maxFileSizeBytes
                           error:(NSError * _Nullable *)outError {
    *outError = nil;

    self = [super init];
    if (self) {
        self->filepath = filepath;
        self->olderFilepath = olderFilepath;

        NSError *err;
        self->rotatingFile = [[RotatingFile alloc] initWithFilepath:filepath
                                                      olderFilepath:olderFilepath
                                                   maxFilesizeBytes:maxFileSizeBytes
                                                              error:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:ExtensionWriterRotatedFileErrorDomain
                                            code:ExtensionWriterRotatedFileErrorInitRotatingFileFailed
                             withUnderlyingError:err];
            return nil;
        }
    }
    return self;
}

- (void)writeData:(NSData*)data error:(NSError * _Nullable *)outError {
    *outError = nil;

    NSError *err;
    [self->rotatingFile writeData:data error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ExtensionWriterRotatedFileErrorDomain
                                        code:ExtensionWriterRotatedFileErrorWriteRotatingFileFailed
                         withUnderlyingError:err];
        return;
    }

}

@end

#endif
