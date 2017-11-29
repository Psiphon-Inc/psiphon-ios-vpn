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

#import "NoticeLogger.h"
#import "SharedConstants.h"
#import "NSDateFormatter+RFC3339.h"
#import "Logging.h"

#define MAX_NOTICE_FILE_SIZE_BYTES 64000
#define NOTICE_FILENAME_EXTENSION "extension_notices"
#define NOTICE_FILENAME_CONTAINER "container_notices"

#define MAX_RETRIES 2

/**
 * All the methods in this class are non-blocking and thread-safe.
 *
 * All timestamps should be RFC3339Milli formatted.
 * Notices are newline "\n" delimited.
 *
 * Since this class is used by the network extension process, it is light
 * in its memory footprint. One side-effect is that the log file will be opened
 * and closed every time noticeError: is called.
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
 * Logging errors in this class:
 *  LOG_ERROR_NO_NOTICE should only be used in this class to log errors.
 *
 */
@implementation NoticeLogger {
    NSLock *writeLock;
    NSString *rotatingFilepath;
    NSString *rotatingOlderFilepath;
    unsigned long long rotatingCurrentFileSize;

    // NSDateFormatter is thread-safe.
    NSDateFormatter *rfc3339Formatter;
}

#pragma mark - Public methods

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;

    dispatch_once(&once, ^{

        #ifdef TARGET_IS_EXTENSION
        sharedInstance = [[self alloc] initWithFilepath:[NoticeLogger extensionRotatingLogNoticesPath]
                                          olderFilepath:[NoticeLogger extensionRotatingOlderLogNoticesPath]];
        #else
        sharedInstance = [[self alloc] initWithFilepath:[NoticeLogger containerRotatingLogNoticesPath]
                                          olderFilepath:[NoticeLogger containerRotatingOlderLogNoticesPath]];
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
    return [[NoticeLogger containerRotatingLogNoticesPath] stringByAppendingString:@".1"];
}

+ (NSString *)extensionRotatingLogNoticesPath {
    return [[[[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path]
      stringByAppendingPathComponent:@NOTICE_FILENAME_EXTENSION];
}

+ (NSString *)extensionRotatingOlderLogNoticesPath {
    return [[NoticeLogger extensionRotatingLogNoticesPath] stringByAppendingString:@".1"];
}

- (void)noticeError:(NSString *)message {
    [self noticeError:message withTimestamp:[rfc3339Formatter stringFromDate:[NSDate date]]];
}

- (void)noticeErrorWithFormat:(NSString *)format, ... {
    NSString *message = nil;
    if (format) {
        va_list args;
        va_start(args, format);
        message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
    }

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
        writeLock = [[NSLock alloc] init];

        rfc3339Formatter = [NSDateFormatter createRFC3339MilliFormatter];

        rotatingFilepath = noticesFilepath;
        rotatingOlderFilepath = olderFilepath;

        NSFileManager *fileManager = [NSFileManager defaultManager];

        // Checks if rotatingFilepath exists, creates the the file if it doesn't exist.
        if ([fileManager fileExistsAtPath:rotatingFilepath]) {
            NSError *err;
            rotatingCurrentFileSize = [[fileManager attributesOfItemAtPath:rotatingFilepath error:&err] fileSize];
            if (err) {
                LOG_ERROR_NO_NOTICE(@"Failed to get log file bytes count");
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

    if (!data) {
        LOG_ERROR_NO_NOTICE(@"Got nil data");
        data = @"nil data";
    }

    NSError *err;

    // Example output format:
    // {"data":{"message":"shutdown operate tunnel"},"noticeType":"Info","showUser":false,"timestamp":"2006-01-02T15:04:05.999-07:00"}
    NSDictionary *outputDic = @{
      @"data": data,
      @"noticeType": noticeType,
      @"showUser": @NO,
      @"timestamp": timestamp
    };

    // The resulting output will be UTF-8 encoded.
    NSData *output = [NSJSONSerialization dataWithJSONObject:outputDic options:kNilOptions error:&err];

    if (err) {
        LOG_ERROR_NO_NOTICE(@"Aborting log write. Failed to serialize JSON object: (%@)", outputDic);
        return;
    }

    [writeLock lock];

    BOOL success = FALSE;
    for (int i = 0; i < MAX_RETRIES && !success; i++) {
        success = [self writeData:output toPath:rotatingFilepath];
    }

    if (rotatingCurrentFileSize > MAX_NOTICE_FILE_SIZE_BYTES) {
        [self rotateFile:rotatingFilepath toFile:rotatingOlderFilepath];
    }

    [writeLock unlock];
}

- (NSFileHandle * _Nullable)fileHandleForPath:(NSString * _Nonnull)path {
    NSError *err;
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:path] error:&err];
    if (err) {
        if (err.code == NSFileReadNoSuchFileError || err.code == NSFileNoSuchFileError) {
            if ([[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]) {
                rotatingCurrentFileSize = 0;
                return [NSFileHandle fileHandleForWritingAtPath:path];
            }
        }

        LOG_ERROR_NO_NOTICE(@"Error opening file handle for file (%@): %@", [path lastPathComponent], err);
        abort();
    }
    return fh;
}

- (BOOL)writeData:(NSData *)data toPath:(NSString *)filePath {

    NSFileHandle *fh;

    @try {
        fh = [self fileHandleForPath:filePath];

        if (fh) {
            // Appends data to the file, and syncs.
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];

            [fh synchronizeFile];

            rotatingCurrentFileSize += [data length] + 1;
            return TRUE;
        }
    }
    @catch (NSException *exception) {
        LOG_ERROR_NO_NOTICE(@"Failed to write log: %@", exception);
    }
    @finally {
        [fh closeFile];
    }

    return FALSE;
}

- (BOOL)rotateFile:(NSString *)filePath toFile:(NSString *)olderFilePath {
    LOG_DEBUG(@"Rotating %@", filePath);

    // Check file size, and rotate if necessary.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *err;

    // Remove old log file if it exists.
    [fileManager removeItemAtPath:olderFilePath error:&err];
    if (err && [err code] != NSFileNoSuchFileError) {
        LOG_ERROR_NO_NOTICE(@"Failed to remove file at path (%@). Error: %@", olderFilePath, err);
        return FALSE;
    }

    err = nil;

    [fileManager copyItemAtPath:filePath toPath:olderFilePath error:&err];
    if (err) {
        LOG_ERROR_NO_NOTICE(@"Failed to move file at path (%@). Error: %@", filePath, err);
        return FALSE;
    }

    if ([fileManager createFileAtPath:filePath contents:nil attributes:nil]) {
        rotatingCurrentFileSize = 0;
        return TRUE;
    }

    return FALSE;
}

@end
