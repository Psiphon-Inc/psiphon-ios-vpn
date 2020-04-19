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

+ (void)writeDataToFile:(NSData*)data
                   path:(NSString*)filepath
                  error:(NSError * _Nullable *)outError {

    *outError = nil;

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:filepath];

    if (fh == nil) {
        *outError = [NSError errorWithDomain:DiskBackedFileErrorDomain
                                        code:DiskBackedFileErrorGetFileHandleFailed
                     andLocalizedDescription:@"file handle nil"];
        return;
    }

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
