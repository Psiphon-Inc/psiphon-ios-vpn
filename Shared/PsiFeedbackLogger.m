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

#import "PsiFeedbackLogger.h"
#import "SharedConstants.h"
#import "NSDateFormatter+RFC3339.h"

#if DEBUG
#define MAX_NOTICE_FILE_SIZE_BYTES 164000
#else
#define MAX_NOTICE_FILE_SIZE_BYTES 64000
#endif

#define NOTICE_FILENAME_EXTENSION "extension_notices"
#define NOTICE_FILENAME_CONTAINER "container_notices"

#define MAX_RETRIES 2

#if DEBUG
#define LOG_ERROR_NO_NOTICE(format, ...) \
  NSLog((@"<ERROR> %s [Line %d]: " format), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define LOG_ERROR_NO_NOTICE(...)
#endif

#define CONVERT_FORMAT_ARGS_TO_NSSTRING(str, format) \
    va_list args; \
    va_start(args, format); \
    str = [[NSString alloc] initWithFormat:format arguments:args]; \
    va_end(args);


#if TARGET_IS_EXTENSION
NSString * const InfoNoticeType = @"ExtensionInfo";
NSString * const ErrorNoticeType = @"ExtensionError";
#else
NSString * const InfoNoticeType = @"ContainerInfo";
NSString * const ErrorNoticeType = @"ContainerError";
#endif

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
@implementation PsiFeedbackLogger {
    NSLock *writeLock;
    NSString *rotatingFilepath;
    NSString *rotatingOlderFilepath;
    unsigned long long rotatingCurrentFileSize;
}

#pragma mark - Class properties

+ (NSString *)containerRotatingLogNoticesPath {
    return [[[[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path]
      stringByAppendingPathComponent:@NOTICE_FILENAME_CONTAINER];
}

+ (NSString *)containerRotatingOlderLogNoticesPath {
    return [PsiFeedbackLogger.containerRotatingLogNoticesPath stringByAppendingString:@".1"];
}

+ (NSString *)extensionRotatingLogNoticesPath {
    return [[[[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:APP_GROUP_IDENTIFIER] path]
      stringByAppendingPathComponent:@NOTICE_FILENAME_EXTENSION];
}

+ (NSString *)extensionRotatingOlderLogNoticesPath {
    return [PsiFeedbackLogger.extensionRotatingLogNoticesPath stringByAppendingString:@".1"];
}

#pragma mark - Public methods

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;

    dispatch_once(&once, ^{

        #if TARGET_IS_EXTENSION
        sharedInstance = [[self alloc] initWithFilepath:PsiFeedbackLogger.extensionRotatingLogNoticesPath
                                          olderFilepath:PsiFeedbackLogger.extensionRotatingOlderLogNoticesPath];
        #else
        sharedInstance = [[self alloc] initWithFilepath:[PsiFeedbackLogger containerRotatingLogNoticesPath]
                                          olderFilepath:[PsiFeedbackLogger containerRotatingOlderLogNoticesPath]];
        #endif
    });

    return sharedInstance;
}

#if TARGET_IS_EXTENSION && DEBUG
+ (void)debug:(NSString *)format, ... {

    NSString *message;
    CONVERT_FORMAT_ARGS_TO_NSSTRING(message, format);
    [[PsiFeedbackLogger sharedInstance] writeMessage:message withNoticeType:@"Extension<Debug>"];

    NSLog(@"<DEBUG> %@", message);
}
#endif

+ (void)info:(NSString *)format, ... {

    NSString *message;
    CONVERT_FORMAT_ARGS_TO_NSSTRING(message, format);
    [[PsiFeedbackLogger sharedInstance] writeMessage:message withNoticeType:InfoNoticeType];

#if DEBUG
    NSLog(@"<INFO> %@", message);
#endif

}

+ (void)info:(NSString *)sourceType message:(NSString *)format, ... {

    NSString *message;
    CONVERT_FORMAT_ARGS_TO_NSSTRING(message, format);
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:InfoNoticeType];

#if DEBUG
    NSLog(@"<INFO> %@", data);
#endif

}

+ (void)error:(NSString *)format, ... {

    NSString *message;
    CONVERT_FORMAT_ARGS_TO_NSSTRING(message, format);
    [[PsiFeedbackLogger sharedInstance] writeMessage:message withNoticeType:ErrorNoticeType];

#if DEBUG
    NSLog(@"<ERROR> %@", message);
#endif

}

+ (void)error:(NSString *)sourceType message:(NSString *)format, ... {

    NSString *message;
    CONVERT_FORMAT_ARGS_TO_NSSTRING(message, format);
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:ErrorNoticeType];

#if DEBUG
    NSLog(@"<ERROR> %@", data);
#endif

}

+ (void)error:(NSString *)sourceType message:(NSString *)message object:(NSError *)error {

//    NSString *message = [NSString stringWithFormat:@"Domain=%@ Description=%@ Code=%ld", error.domain, error.localizedDescription, (long) error.code];
    NSDictionary *data = @{sourceType : @{@"message" : message,
                                          @"NSError" : @{@"domain" : error.domain,
                                                         @"code"   : @(error.code),
                                                         @"description" : error.localizedDescription}}};

    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:ErrorNoticeType];

#if DEBUG
    NSLog(@"<ERROR> %@", data);
#endif

}

+ (void)logNoticeWithType:(NSString *)noticeType message:(NSString *)message timestamp:(NSString *)timestamp {
    [[PsiFeedbackLogger sharedInstance] writeData:@{@"message": message} noticeType:noticeType timestamp:timestamp];
}

# pragma mark - Private methods

- (instancetype)initWithFilepath:(NSString *)noticesFilepath olderFilepath:(NSString *)olderFilepath {
    self = [super init];
    if (self) {
        writeLock = [[NSLock alloc] init];

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

- (void)writeMessage:(NSString *)message withNoticeType:(NSString *)noticeType {
    [self writeMessage:message withNoticeType:noticeType andTimestamp:[[NSDateFormatter sharedRFC3339MilliDateFormatter] stringFromDate:[NSDate date]]];
}

- (void)writeMessage:(NSString *)message withNoticeType:(NSString *)noticeType andTimestamp:(NSString *)timestamp {
    [self writeData:@{@"message": message} noticeType:noticeType timestamp:timestamp];
}

- (void)writeData:(NSDictionary<NSString *, NSString *> *)data noticeType:(NSString *)noticeType {
    [self writeData:data
         noticeType:noticeType
          timestamp:[[NSDateFormatter sharedRFC3339MilliDateFormatter] stringFromDate:[NSDate date]]];
}

- (void)writeData:(NSDictionary<NSString *, NSString *> *)data noticeType:(NSString *)noticeType timestamp:(NSString *)timestamp {

    if (!data) {
        LOG_ERROR_NO_NOTICE(@"output notice nil data");
        data = @{@"data" : @"nil data"};
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
