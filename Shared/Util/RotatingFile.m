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

#import "RotatingFile.h"
#import "NSError+Convenience.h"

#pragma mark - NSError key

NSErrorDomain _Nonnull const RotatingFileErrorDomain = @"RotatingFileErrorDomain";

typedef NS_ERROR_ENUM(RunningStatErrorDomain, RunningStatErrorCode) {
    RotatingFileErrorCreateFileFailed = 1,
    RotatingFileErrorRemoveFileFailed = 2,
    RotatingFileErrorWriteFileFailed = 3,
    RotatingFileErrorRotateFileFailed = 4,
    RotatingFileErrorGetFileHandleFailed = 5,
    RotatingFileErrorGetFileAttrsFailed = 6,
    RotatingFileErrorFlushMemoryFailed = 7,
};

@implementation RotatingFile {
    NSString *rotatingFilepath;
    NSString *rotatingOlderFilepath;
    unsigned long long rotatingCurrentFileSize;
    unsigned long long maxFileSizeBytes;
}

#pragma mark - Public methods

- (instancetype)initWithFilepath:(NSString *)filepath
                   olderFilepath:(NSString *)olderFilepath
                maxFilesizeBytes:(unsigned long long)maxFileSizeBytes
                           error:(NSError * _Nullable *)outError {

    *outError = nil;

    self = [super init];
    if (self) {
        self->rotatingFilepath = filepath;
        self->rotatingOlderFilepath = olderFilepath;
        self->maxFileSizeBytes = maxFileSizeBytes;

        NSFileManager *fileManager = [NSFileManager defaultManager];

        // Checks if rotatingFilepath exists, creates the the file if it doesn't exist.
        if ([fileManager fileExistsAtPath:rotatingFilepath]) {
            NSError *err;
            self->rotatingCurrentFileSize = [[fileManager attributesOfItemAtPath:self->rotatingFilepath error:&err] fileSize];
            if (err) {
                *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                                code:RotatingFileErrorGetFileAttrsFailed
                                 withUnderlyingError:err];
                return nil;
            }
        } else {
            if ([fileManager createFileAtPath:rotatingFilepath contents:nil attributes:nil]) {
                // Set the current file size to 0.
                self->rotatingCurrentFileSize = 0;
            } else {
                *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                                code:RotatingFileErrorCreateFileFailed
                             andLocalizedDescription:[NSString stringWithFormat:@"Failed to create: %@", self->rotatingFilepath.lastPathComponent]];
                return nil;
            }
        }
    }

    return self;
}

- (void)writeData:(NSData *)data error:(NSError * _Nullable *)outError {
    *outError = nil;
    NSError *err;

    [self writeData:data toPath:self->rotatingFilepath error:&err];
    if (err != nil) {
        *outError = err;
    }
}

#pragma mark - Private methods

- (void)writeData:(NSData *)data
           toPath:(NSString *)filePath
            error:(NSError * _Nullable *)outError {

    *outError = nil;

    if (self->rotatingCurrentFileSize > self->maxFileSizeBytes) {
        NSError *err;
        [self rotateFile:rotatingFilepath toFile:rotatingOlderFilepath error:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                            code:RotatingFileErrorRotateFileFailed
                             withUnderlyingError:err];
            return;
        }
    }

    NSFileHandle *fh;

    @try {
        NSError *err;
        fh = [self fileHandleForPath:filePath error:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                            code:RotatingFileErrorGetFileHandleFailed
                         andLocalizedDescription:@"Error getting filehandle"];
            return;
        }

        if (!fh) {
            *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                            code:RotatingFileErrorGetFileHandleFailed
                         andLocalizedDescription:[NSString stringWithFormat:@"File handle nil"]
                             withUnderlyingError:err];
            return;
        }

        // Appends data to the file, and syncs.
        [fh seekToEndOfFile];
        [fh writeData:data];

        if (@available(iOS 13.0, *)) {
            [fh synchronizeAndReturnError:&err];
            if (err != nil) {
                *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                                code:RotatingFileErrorFlushMemoryFailed
                                 withUnderlyingError:err];
                return;
            }
        } else {
            // Fallback on earlier versions
            [fh synchronizeFile];
        }

        self->rotatingCurrentFileSize += [data length];
    }
    @catch (NSException *exception) {
        *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                        code:RotatingFileErrorWriteFileFailed
                     andLocalizedDescription:[NSString stringWithFormat:@"Failed to write log: %@", exception]];
        [fh closeFile];
        return;
    }
    @finally {}

    [fh closeFile];
    return;
}

- (NSFileHandle * _Nullable)fileHandleForPath:(NSString * _Nonnull)path
                                        error:(NSError * _Nullable *)outError {
    *outError = nil;
    NSError *err;
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:path] error:&err];
    if (err) {
        if (err.code == NSFileReadNoSuchFileError || err.code == NSFileNoSuchFileError) {
            if ([[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]) {
                self->rotatingCurrentFileSize = 0;
                return [NSFileHandle fileHandleForWritingAtPath:path];
            }
        }

        *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                        code:RotatingFileErrorGetFileHandleFailed
                     andLocalizedDescription:[NSString stringWithFormat:@"Error opening file handle for file %@", path.lastPathComponent]
                         withUnderlyingError:err];
        return nil;
    }
    return fh;
}

- (void)rotateFile:(NSString *)filePath
            toFile:(NSString *)olderFilePath
             error:(NSError * _Nullable *)outError {

    *outError = nil;

    // Check file size, and rotate if necessary.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *err;

    // Remove old log file if it exists.
    [fileManager removeItemAtPath:olderFilePath error:&err];
    if (err && [err code] != NSFileNoSuchFileError) {
        *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                        code:RotatingFileErrorRemoveFileFailed
                     andLocalizedDescription:[NSString stringWithFormat:@"Failed to remove file at path: %@", olderFilePath]
                         withUnderlyingError:err];
        return;
    }

    err = nil;

    [fileManager moveItemAtPath:filePath toPath:olderFilePath error:&err];
    if (err) {
        *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                        code:RotatingFileErrorRemoveFileFailed
                     andLocalizedDescription:[NSString stringWithFormat:@"Failed to move file: %@", filePath.lastPathComponent]
                         withUnderlyingError:err];
        return;
    }

    if ([fileManager createFileAtPath:filePath contents:nil attributes:nil]) {
        self->rotatingCurrentFileSize = 0;
        return;
    }

    *outError = [NSError errorWithDomain:RotatingFileErrorDomain
                                    code:RotatingFileErrorCreateFileFailed
                 andLocalizedDescription:[NSString stringWithFormat:@"Failed to create: %@",
                                          filePath.lastPathComponent]];

    return;
}

@end
