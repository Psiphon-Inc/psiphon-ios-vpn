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

#import "Notice.h"
#import "SharedConstants.h"
#import "NSDateFormatter+RFC3339.h"
#import "Logging.h"

#define MAX_NOTICE_FILE_SIZE_BYTES 64000
#define NOTICE_FILENAME_EXTENSION "extension_notices"
#define NOTICE_FILENAME_CONTAINER "container_notices"

/**
 * All the methods in this class are non-blocking and thread-safe.
 *
 * All timestamps should be RFC3339Milli formatted.
 * Notices are newline "\n" delimited.
 *
 * Since this class is used by the network extension process, it is light
 * in its footprint. One side-effect is that the log file will be opened
 * and closed ever
 *
 * Notices are encoded in JSON, in the same format as psiphon-tunnel-core,
 *
 * Here's an example:
 *
 * {"data":{"message":"shutdown operate tunnel"},"noticeType":"Info","showUser":false,"timestamp":"2006-01-02T15:04:05.999-07:00"}
 *
 * Similar to psiphon-tunnel-core all notices have the following fields:
 * - "noticeType": the type of notice, which indicates the meaning of the notice along with what's in the data payload.
 * - "data": additional structured data payload.
 * - "showUser": whether the information should be displayed to the user.
 * - "timestamp": UTC timezone, RFC3339Milli format timestamp for notice event.
 *
 */

@implementation Notice {
    dispatch_queue_t serialWorkQueue;

    NSString *rotatingFilepath;
    NSString *rotatingOlderFilepath;
    unsigned long long rotatingCurrentFileSize;
    NSDateFormatter *rfc3339Formatter;
}

#pragma mark - Public methods

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;

    dispatch_once(&once, ^{

        #ifdef TARGET_IS_EXTENSION
        sharedInstance = [[self alloc] initWithFilepath:[Notice extensionRotatingLogNoticesPath] 
                                          olderFilepath:[Notice extensionRotatingOlderLogNoticesPath]];
        #else
        sharedInstance = [[self alloc] initWithFilepath:[Notice containerRotatingLogNoticesPath] 
                                          olderFilepath:[Notice containerRotatingOlderLogNoticesPath]];
        #endif
    });

    return sharedInstance;
}

+ (NSString *)containerRotatingLogNoticesPath {
    return [[[[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path]
      stringByAppendingPathComponent:@NOTICE_FILENAME_CONTAINER];
}

+ (NSString *)containerRotatingOlderLogNoticesPath {
    return [[Notice containerRotatingLogNoticesPath] stringByAppendingString:@".1"];
}

+ (NSString *)extensionRotatingLogNoticesPath {
    return [[[[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path]
      stringByAppendingPathComponent:@NOTICE_FILENAME_EXTENSION];
}

+ (NSString *)extensionRotatingOlderLogNoticesPath {
    return [[Notice extensionRotatingLogNoticesPath] stringByAppendingString:@".1"];
}

- (void)noticeError:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self noticeError:message withTimestamp:[rfc3339Formatter stringFromDate:[NSDate date]]];
}

- (void)noticeError:(NSString *)message withTimestamp:(NSString *)timestamp {
    NSString *noticeType;
#ifdef TARGET_IS_EXTENSION
    noticeType = @"Extension";
#else
    noticeType = @"Container";
#endif
    [self outputNotice:message withNoticeType:noticeType andTimestamp:timestamp];
}

# pragma mark - Private methods

- (instancetype)initWithFilepath:(NSString *)noticesFilepath olderFilepath:(NSString *)olderFilepath {
    self = [super init];
    if (self) {
         serialWorkQueue = dispatch_queue_create([APP_GROUP_IDENTIFIER @"noticeWorkQueue" UTF8String],
           DISPATCH_QUEUE_SERIAL);
        rfc3339Formatter = [NSDateFormatter createRFC3339MilliFormatter];

        rotatingFilepath = noticesFilepath;
        rotatingOlderFilepath = olderFilepath;

        NSFileManager *fileManager = [NSFileManager defaultManager];

        // Checks if rotatingFilepath exists, creates the the file if it doesn't exist.
        if ([fileManager fileExistsAtPath:rotatingFilepath]) {

            NSError *err;
            rotatingCurrentFileSize = [[fileManager attributesOfItemAtPath:rotatingFilepath error:&err] fileSize];

            if (err) {
                LOG_ERROR(@"Failed to get log file bytes count");
                // This is fatal, return nil.
                return nil;
            }

        } else {
            if ([fileManager createFileAtPath:rotatingFilepath contents:nil attributes:nil]) {
                // Set the current file size to 0.
                rotatingCurrentFileSize = 0;
            } else {
                // If failed to create log file, return nil;
                return nil;
            }
        }

    }
    return self;
}

- (void)outputNotice:(NSString *)data withNoticeType:(NSString *)noticeType andTimestamp:(NSString *)timestamp {

    dispatch_async(serialWorkQueue, ^{

        NSError *err;

        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:rotatingFilepath]
                                                                     error:&err];
        if (err) {
            LOG_ERROR(@"Failed to open file handle for path (%@). Error: %@", rotatingFilepath, err);
            return;
        }

        // Prepare file handle for appending.
        [fileHandle seekToEndOfFile];

        // Example output format:
        // {"data":{"message":"shutdown operate tunnel"},"noticeType":"Info","showUser":false,"timestamp":"2006-01-02T15:04:05.999-07:00"}
        NSData *output = [[NSString
          stringWithFormat:@"{\"data\":\"%@\",\"noticeType\":\"%@\",\"showUser\":false,\"timestamp\":\"%@\"}\n",
                               data, noticeType, timestamp] dataUsingEncoding:NSUTF8StringEncoding];
        [fileHandle writeData:output];

        // Sync and close file before (possible) rotation.
        [fileHandle synchronizeFile];
        [fileHandle closeFile];

        rotatingCurrentFileSize += [output length];

        // Check file size, and rotate if necessary.
        NSFileManager *fileManager = [NSFileManager defaultManager];

        if (rotatingCurrentFileSize > MAX_NOTICE_FILE_SIZE_BYTES) {
            
            LOG_DEBUG(@"Rotating notices for type (%@)", noticeType);
            
            // Remove old log file if it exists.
            if ([fileManager fileExistsAtPath:rotatingOlderFilepath]) {
                if ([fileManager removeItemAtPath:rotatingOlderFilepath error:&err]) {
                    [fileManager moveItemAtPath:rotatingFilepath toPath:rotatingOlderFilepath error:&err];
                }

                // Do no abort, continue with truncating original log.
                if (err) {
                    LOG_ERROR(@"Failed to rotate log file at path (%@). Error: %@", rotatingFilepath, err);
                    err = nil;
                }
            }

            // Truncate log file.
            NSFileHandle *truncationFileHandle = [NSFileHandle fileHandleForUpdatingAtPath:rotatingFilepath];
            if (truncationFileHandle) {
                [truncationFileHandle truncateFileAtOffset:0];
                [truncationFileHandle closeFile];

                rotatingCurrentFileSize = 0;
            } else {
                LOG_ERROR(@"Failed to truncate notices file for type (%@)", noticeType);
            }
        }
    });
}

@end
