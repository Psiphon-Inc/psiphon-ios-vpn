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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString * PsiFeedbackLogType;

@interface PsiFeedbackLogger : NSObject

@property (class, nonatomic, readonly) NSString * containerRotatingLogNoticesPath;
@property (class, nonatomic, readonly) NSString * containerRotatingOlderLogNoticesPath;
@property (class, nonatomic, readonly) NSString * extensionRotatingLogNoticesPath;
@property (class, nonatomic, readonly) NSString * extensionRotatingOlderLogNoticesPath;

+ (instancetype)sharedInstance;

#if TARGET_IS_EXTENSION && DEBUG
+ (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
#endif

+ (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

+ (void)infoWithType:(PsiFeedbackLogType)sourceType message:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

+ (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

+ (void)errorWithType:(PsiFeedbackLogType)sourceType message:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

+ (void)errorWithType:(PsiFeedbackLogType)sourceType message:(NSString *)message object:(NSError *)error;

+ (void)logNoticeWithType:(NSString *)noticeType message:(NSString *)message timestamp:(NSString *)timestamp;

@end

NS_ASSUME_NONNULL_END
