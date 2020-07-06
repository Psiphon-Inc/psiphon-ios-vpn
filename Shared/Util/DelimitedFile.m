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

#import "DelimitedFile.h"
#import "NSError+Convenience.h"

#pragma mark - NSError key

NSErrorDomain _Nonnull const DelimitedFileErrorDomain = @"DelimitedFileErrorDomain";

@interface DelimitedFile ()

@property (strong, nonatomic) NSFileHandle *fileHandle;

@property (nonatomic) NSUInteger bytesRead;
@property (nonatomic) NSUInteger bytesReturned;

@end

@implementation DelimitedFile {
    // Configuration
    NSUInteger chunkSize;

    // Operation
    BOOL done;
    NSMutableString *decodedBuffer;
}

- (void)dealloc {
    if (self.fileHandle != nil) {
        [self.fileHandle closeFile];
    }
}

#pragma mark - Public methods

- (instancetype)initWithFilepath:(NSString*)filepath
                       chunkSize:(NSUInteger)chunkSize
                           error:(NSError * _Nullable *)outError {
    self = [super init];
    if (self) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:filepath]) {
            *outError = [NSError errorWithDomain:DelimitedFileErrorDomain
                                            code:DelimitedFileErrorFileDoesNotExist
                         andLocalizedDescription:[NSString stringWithFormat:@"File not found: %@", filepath]];
            return nil;
        }
        self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:filepath];
        if (self.fileHandle == nil) {
            *outError = [NSError errorWithDomain:DelimitedFileErrorDomain
                                            code:DelimitedFileErrorGetFileHandleFailed
                         andLocalizedDescription:[NSString stringWithFormat:@"Failed to get file handle for file: %@", filepath]];
            return nil;
        }
        self->chunkSize = chunkSize;
        self.bytesRead = 0;
        self.bytesReturned = 0;
        self->decodedBuffer = [[NSMutableString alloc] init];
    }
    return self;
}

- (NSString*)readLineWithError:(NSError * _Nullable *)outError {

    *outError = nil;
    if (self->done) {
        return nil;
    }

    // Check if there are any lines in the buffer
    if ([self->decodedBuffer length] > 0) {
        NSString *line = [self lineFromCurrentBuffer];
        if (line != nil) {
            // Add string plus newline.
            // Note: calculation is only correct because one ASCII character equals one byte.
            self.bytesReturned += [line length] + 1;
            return line;
        }
    }

    // Read until newline or EOF
    while(true) {
        NSData *buffer = nil;

        if (@available(iOS 13.0, *)) {
            NSError *err;
            buffer = [self.fileHandle readDataUpToLength:self->chunkSize error:&err];
            if (err != nil) {
                *outError = [NSError errorWithDomain:DelimitedFileErrorDomain
                                                code:DelimitedFileErrorReadFailed
                                 withUnderlyingError:err];
                self->done = TRUE;
                return nil;
            }
        } else {
            @try {
                buffer = [self.fileHandle readDataOfLength:self->chunkSize];
            }
            @catch (NSException *exception) {
                *outError = [NSError errorWithDomain:DelimitedFileErrorDomain
                                                code:DelimitedFileErrorReadFailed
                             andLocalizedDescription:[NSString stringWithFormat:@"Exception reading file handle: %@", exception.description]];
                self->done = TRUE;
                return nil;
            }
        }

        if ([buffer length] == 0) {
            if ([self->decodedBuffer length] > 0) {
                // Return the remainder
                NSString *line = self->decodedBuffer;
                self->done = TRUE;
                // Note: calculation is only correct because one ASCII character equals one byte.
                self.bytesReturned += [line length];
                return line;
            }

            self->done = TRUE;
            return nil;
        }

        self.bytesRead += [buffer length];

        NSString *chunk = [[NSString alloc] initWithData:buffer encoding:NSASCIIStringEncoding];
        if (chunk != nil) {
            [self->decodedBuffer appendString:chunk];
        } else {
            NSString *b64 = [buffer base64EncodedStringWithOptions:kNilOptions];
            *outError = [NSError errorWithDomain:DelimitedFileErrorDomain
                                            code:DelimitedFileErrorDecodingFailed
                         andLocalizedDescription:[NSString stringWithFormat:@"Failed to decode: %@", b64]];
            self->done = TRUE;
            return nil;
        }

        // Look for a newline
        NSString *line = [self lineFromCurrentBuffer];
        if (line != nil) {
            // Add string plus newline.
            // Note: calculation is only correct because one ASCII character equals one byte.
            self.bytesReturned += [line length] + 1;
            return line;
        }
    }

    return nil;
}

#pragma mark - Private methods

- (NSString*)lineFromCurrentBuffer {
    NSRange range = [self->decodedBuffer rangeOfString:@"\n"];
    if (range.location == NSNotFound) {
        return nil;
    } else {
        NSString *line = [self->decodedBuffer substringWithRange:NSMakeRange(0, range.location)];
        [self->decodedBuffer deleteCharactersInRange:NSMakeRange(0, range.location + range.length)];
        return line;
    }
}

@end
