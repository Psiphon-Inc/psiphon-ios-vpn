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
#import "RotatingFile.h"
#import "SharedConstants.h"
#import "NSDate+PSIDateExtension.h"
#import "Nullity.h"
#import "Asserts.h"

#if DEBUG
unsigned long long MAX_NOTICE_FILE_SIZE_BYTES = 164000;
#else
unsigned long long MAX_NOTICE_FILE_SIZE_BYTES = 64000;
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
NSString * const WarnNoticeType = @"ExtensionWarn";
NSString * const ErrorNoticeType = @"ExtensionError";
NSString * const FatalErrorNoticeType = @"ExtensionFatalError";
#else
NSString * const InfoNoticeType = @"ContainerInfo";
NSString * const WarnNoticeType = @"ContainerWarn";
NSString * const ErrorNoticeType = @"ContainerError";
NSString * const FatalErrorNoticeType = @"ContainerFatalError";
#endif


PsiFeedbackLogType const FeedbackInternalLogType = @"FeedbackLoggerInternal";

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
    RotatingFile *rotatedFile;
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

+ (void)infoWithType:(PsiFeedbackLogType)sourceType message:(NSString *)message {
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:InfoNoticeType];
    
#if DEBUG
    NSLog(@"<INFO> %@", data);
#endif
}

+ (void)infoWithType:(PsiFeedbackLogType)sourceType format:(NSString *)format, ... {

    NSString *message;
    CONVERT_FORMAT_ARGS_TO_NSSTRING(message, format);
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:InfoNoticeType];

#if DEBUG
    NSLog(@"<INFO> %@", data);
#endif

}

+ (void)infoWithType:(PsiFeedbackLogType)sourceType json:(NSDictionary*_Nonnull)json {

    NSDictionary *data = @{sourceType : json};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:InfoNoticeType];

#if DEBUG
    NSLog(@"<INFO> %@", data);
#endif

}

+ (void)warnWithType:(PsiFeedbackLogType)sourceType message:(NSString *)message {
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:WarnNoticeType];
    
#if DEBUG
    NSLog(@"<WARN> %@", data);
#endif
}

+ (void)warnWithType:(PsiFeedbackLogType)sourceType format:(NSString *)format, ... {

    NSString *message;
    CONVERT_FORMAT_ARGS_TO_NSSTRING(message, format);
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:WarnNoticeType];

#if DEBUG
    NSLog(@"<WARN> %@", data);
#endif

}

+ (void)warnWithType:(PsiFeedbackLogType)sourceType message:(NSString *)message object:(NSError *)error {

    NSDictionary *data = [PsiFeedbackLogger generateDictionaryWithSource:sourceType message:message error:error];
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:WarnNoticeType];

#if DEBUG
    NSLog(@"<WARN> %@", data);
#endif

}

+ (void)warnWithType:(PsiFeedbackLogType)sourceType json:(NSDictionary *_Nonnull)json {
    NSDictionary *data = @{sourceType : json};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:WarnNoticeType];

#if DEBUG
    NSLog(@"<WARN> %@", data);
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

+ (void)error:(NSError*)error message:(NSString*)message {

    NSDictionary *data = [PsiFeedbackLogger generateDictionaryWithSource:ErrorNoticeType message:message error:error];
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:ErrorNoticeType];

#if DEBUG
    NSLog(@"<ERROR> %@", data);
#endif

}

+ (void)errorWithType:(PsiFeedbackLogType)sourceType message:(NSString *)message {
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:ErrorNoticeType];
    
#if DEBUG
    NSLog(@"<ERROR> %@", data);
#endif
}

+ (void)errorWithType:(PsiFeedbackLogType)sourceType format:(NSString *)format, ... {

    NSString *message;
    CONVERT_FORMAT_ARGS_TO_NSSTRING(message, format);
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:ErrorNoticeType];

#if DEBUG
    NSLog(@"<ERROR> %@", data);
#endif

}

+ (void)errorWithType:(PsiFeedbackLogType)sourceType json:(NSDictionary*_Nonnull)json {

    NSDictionary *data = @{sourceType : json};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:ErrorNoticeType];

#if DEBUG
    NSLog(@"<ERROR> %@", data);
#endif

}

+ (void)errorWithType:(PsiFeedbackLogType)sourceType message:(NSString *)message object:(NSError *)error {

    NSDictionary *data = [PsiFeedbackLogger generateDictionaryWithSource:sourceType message:message error:error];
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:ErrorNoticeType];

#if DEBUG
    NSLog(@"<ERROR> %@", data);
#endif

}

+ (void)fatalErrorWithType:(PsiFeedbackLogType)sourceType message:(NSString *)message {
    NSDictionary *data = @{sourceType : message};
    [[PsiFeedbackLogger sharedInstance] writeData:data noticeType:FatalErrorNoticeType];
    
#if DEBUG
    NSLog(@"<FATAL> %@", data);
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
        NSError *err;
        self->rotatedFile = [[RotatingFile alloc]
                             initWithFilepath:noticesFilepath
                             olderFilepath:olderFilepath
                             maxFilesizeBytes:MAX_NOTICE_FILE_SIZE_BYTES
                             error:&err];
        if (err != nil) {
            LOG_ERROR_NO_NOTICE(@"Failed to init rotating notices file: %@", err);
            return nil;
        }

    }
    return self;
}

- (void)writeMessage:(NSString *)message withNoticeType:(NSString *)noticeType {
    [self writeMessage:message withNoticeType:noticeType andTimestamp:[NSDate nowRFC3339Milli]];
}

- (void)writeMessage:(NSString *)message withNoticeType:(NSString *)noticeType andTimestamp:(NSString *)timestamp {
    [self writeData:@{@"message": message} noticeType:noticeType timestamp:timestamp];
}

- (void)writeData:(NSDictionary *)data noticeType:(NSString *)noticeType {
    [self writeData:data
         noticeType:noticeType
          timestamp:[NSDate nowRFC3339Milli]];
}

- (void)writeData:(NSDictionary *_Nullable)data
       noticeType:(NSString *_Nonnull)noticeType
        timestamp:(NSString *_Nonnull)timestamp {

    if ([Nullity isNil:data]) {
        data = @{@"data" : @"nilData"};
        PSIAssert(FALSE);
    }

    if ([Nullity isEmpty:noticeType]) {
        noticeType = @"emptyNoticeType";
        PSIAssert(FALSE);
    }

    if ([Nullity isEmpty:timestamp]) {
        timestamp = [NSDate nowRFC3339Milli];
        PSIAssert(FALSE);
    }

    NSError *err;

    // Example output format:
    // {"data":{"message":"shutdown operate tunnel"},"noticeType":"Info","showUser":false,"timestamp":"2006-01-02T15:04:05.999-07:00"}
    NSDictionary *outputDic = @{
      @"data": data,
      @"noticeType": noticeType,
      @"showUser": [NSNumber numberWithBool:NO],
      @"timestamp": timestamp
    };

    if (![NSJSONSerialization isValidJSONObject:outputDic]) {
        [PsiFeedbackLogger errorWithType:FeedbackInternalLogType format:@"invalid log dictionary"];

#if DEBUG
        abort();
#endif

        return;
    }

    // The resulting output will be UTF-8 encoded.
    NSData *output = [NSJSONSerialization dataWithJSONObject:outputDic options:kNilOptions error:&err];

    if (err) {
        LOG_ERROR_NO_NOTICE(@"Aborting log write. Failed to serialize JSON object: (%@)", outputDic);
        return;
    }

    [writeLock lock];

    for (int i = 0; i < MAX_RETRIES; i++) {
        // Add newline delimiter
        NSMutableData *data = [NSMutableData dataWithData:output];
        [data appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];

        NSError *err;
        [self->rotatedFile writeData:data error:&err];
        if (err != nil) {
            LOG_ERROR_NO_NOTICE(@"Failed to write data: %@", err);
            continue;
        }
        break;
    }

    [writeLock unlock];
}

#pragma mark - Log generating methods

// Unpacks a NSError object to a dictionary representation fit for logging.
+ (NSDictionary *_Nonnull)unpackError:(NSError *_Nullable)error {

    if ([Nullity isNil:error]) {
        return @{@"error": @"nilError"};
    }

    NSMutableDictionary *errorDic = [NSMutableDictionary dictionary];
    errorDic[@"domain"] = error.domain;
    errorDic[@"code"] = @(error.code);

    if (error.userInfo) {
        if (![Nullity isEmpty:error.userInfo[NSLocalizedDescriptionKey]]) {
            errorDic[@"description"] = error.userInfo[NSLocalizedDescriptionKey];
        }
        if (![Nullity isNil:error.userInfo[NSUnderlyingErrorKey]]) {
            errorDic[@"underlyingError"] = [PsiFeedbackLogger unpackError:error.userInfo[NSUnderlyingErrorKey]];
        }
    }

    return errorDic;
}

// Generates a dictionary fit for logging with the provided fields.
+ (NSDictionary *_Nonnull)generateDictionaryWithSource:(NSString *_Nullable)sourceType
                                               message:(NSString *_Nullable)message
                                                 error:(NSError *_Nullable)error {

    if ([Nullity isEmpty:sourceType]) {
        sourceType = @"nilSourceType";
    }

    if ([Nullity isEmpty:message]) {
        message = @"nilMessage";
    }

    return @{sourceType : @{@"message" : message,
                            @"NSError" : [PsiFeedbackLogger unpackError:error]}};

}

+ (id _Nonnull)safeValue:(id _Nullable)value {
    if (value == nil) {
        return NSNull.null;
    } else if ([value isKindOfClass:[NSDate class]]) {
        return [value RFC3339String];
    }
    return value;
}

@end
