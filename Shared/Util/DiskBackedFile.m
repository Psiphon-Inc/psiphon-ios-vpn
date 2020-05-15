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

#import "DiskBackedFile.h"
#import "NSError+Convenience.h"

NSErrorDomain _Nonnull const DiskBackedFileErrorDomain = @"DiskBackedFileErrorDomain";

@implementation DiskBackedFile

#pragma mark - Public methods

+ (BOOL)fileExistsAtPath:(NSString*)filepath {
    NSFileManager *fileManager = [DiskBackedFile defaultFileManager];
    return [fileManager fileExistsAtPath:filepath];
}

+ (unsigned long long)fileSizeAtPath:(NSString*)filepath
                               error:(NSError * _Nullable *)outError {
    *outError = nil;

    NSError *err;
    NSDictionary<NSFileAttributeKey, id> *attributes = [DiskBackedFile fileAttributesAtPath:filepath
                                                                                      error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                        code:DiskBackedFileErrorGetAttributesFailed
                         withUnderlyingError:err];
        return 0;
    }

    return [attributes fileSize];
}

+ (NSUInteger)fileSystemFileNumber:(NSString*)filepath
                             error:(NSError * _Nullable *)outError {
    *outError = nil;

    NSError *err;
    NSDictionary<NSFileAttributeKey, id> *attributes = [DiskBackedFile fileAttributesAtPath:filepath
                                                                                      error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                        code:DiskBackedFileErrorGetAttributesFailed
                         withUnderlyingError:err];
        return 0;
    }

    return [attributes fileSystemFileNumber];
}

+ (NSData *)fileDataAtPath:(NSString*)filepath error:(NSError * _Nullable *)outError {
    NSError *err;
    NSData *data = [NSData dataWithContentsOfFile:filepath options:kNilOptions error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                        code:DiskBackedFileErrorReadFailed
                         withUnderlyingError:err];
        return nil;
    }

    return data;
}

+ (void)createFileAtPath:(NSString*)filepath
                    data:(NSData*)data
                   error:(NSError * _Nullable *)outError {
    *outError = nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:filepath]) {
        NSError *err;
        BOOL success = [fm removeItemAtPath:filepath error:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                            code:DiskBackedFileErrorDeleteFileFailed
                             withUnderlyingError:err];
            return;
        }
        if (success == FALSE) {
            *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                            code:DiskBackedFileErrorDeleteFileFailed];
            return;
        }
    }

    BOOL success = [fm createFileAtPath:filepath contents:nil attributes:nil];
    if (success == FALSE) {
        *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                        code:DiskBackedFileErrorCreateFileFailed];
        return;
    }

    NSError *err;
    [DiskBackedFile writeDataToFileAtPath:filepath data:data error:&err];
    if (err != nil) {
       *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                       code:DiskBackedFileErrorWriteFailed
                        withUnderlyingError:err];
       return;
    }
}

+ (void)writeDataToFileAtPath:(NSString*)filepath
                         data:(NSData*)data
                        error:(NSError * _Nullable *)outError {

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:filepath];

    if (fh == nil) {
        *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                        code:DiskBackedFileErrorGetFileHandleFailed
                     andLocalizedDescription:@"file handle nil"];
        return;
    }

    NSError *err;
    [DiskBackedFile writeDataToFileHandle:fh
                                     data:data
                                    error:&err];
    if (err != nil) {
        *outError = err;
    }
}

+ (void)appendDataToFileAtPath:(NSString*)filepath
                          data:(NSData*)data
                         error:(NSError * _Nullable *)outError {

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:filepath];

    if (fh == nil) {
        *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                        code:DiskBackedFileErrorGetFileHandleFailed
                     andLocalizedDescription:@"file handle nil"];
        return;
    }

    [fh seekToEndOfFile];

    NSError *err;
    [DiskBackedFile writeDataToFileHandle:fh
                                     data:data
                                    error:&err];
    if (err != nil) {
        *outError = err;
    }
}


+ (void)writeDataToFileHandle:(NSFileHandle*)fh
                         data:(NSData*)data
                        error:(NSError * _Nullable *)outError {

    *outError = nil;

    NSError *err;
    if (@available(iOS 13.0, *)) {
        BOOL success = [fh writeData:data error:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                            code:DiskBackedFileErrorWriteFailed
                             withUnderlyingError:err];
            [fh closeFile];
            return;
        }
        if (success == FALSE) {
            *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                            code:DiskBackedFileErrorWriteFailed
                         andLocalizedDescription:@"success is false"];
            [fh closeFile];
            return;
        }

        [fh synchronizeAndReturnError:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                            code:DiskBackedFileErrorSyncFileFailed
                             withUnderlyingError:err];
            [fh closeFile];
            return;
        }

        return;
    } else {
        // Fallback on earlier versions
        @try {
            [fh writeData:data];
        }
        @catch(NSException *exception) {
            *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                            code:DiskBackedFileErrorWriteFailed
                         andLocalizedDescription:[NSString stringWithFormat:@"Exception writing file %@",
                                                  exception.description]];
            [fh closeFile];
            return;
        }
        @finally{}

        [fh synchronizeFile];
    }

    [fh closeFile];
    return;
}

#pragma mark - Private methods

+ (NSDictionary<NSFileAttributeKey, id>*)fileAttributesAtPath:(NSString*)filepath
                                                        error:(NSError * _Nullable *)outError {

    *outError = nil;
    NSFileManager *fileManager = [DiskBackedFile defaultFileManager];
    return [fileManager attributesOfItemAtPath:filepath error:outError];
}

+ (NSFileManager*)defaultFileManager {
    return [NSFileManager defaultManager];
}

@end
