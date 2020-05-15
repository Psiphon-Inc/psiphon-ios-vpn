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

#import "JetsamEvent.h"
#import "NSError+Convenience.h"

#pragma mark - NSCoding keys

// Used for tracking the archive schema
NSUInteger const JetsamEventArchiveVersion1 = 1;

// NSCoder keys (must be unique)
NSString *_Nonnull const JetsamEventArchiveVersionIntegerCoderKey = @"version.integer";
NSString *_Nonnull const JetsamEventRunningTimeCoderKey = @"running_time.dbl";
NSString *_Nonnull const JetsamEventDateCoderKey = @"jetsam_date.dbl";
NSString *_Nonnull const JetsamEventAppVersionCoderKey = @"app_version.dbl";


@interface JetsamEvent ()

@property (nonatomic, strong) NSString *appVersion;
@property (nonatomic, assign) NSTimeInterval runningTime;
@property (nonatomic, assign) NSTimeInterval jetsamDate;

@end

@implementation JetsamEvent

+ (instancetype)jetsamEventWithAppVersion:(NSString*)appVersion
                              runningTime:(NSTimeInterval)runningTime
                               jetsamDate:(NSTimeInterval)jetsamDate {

    JetsamEvent *x = [[JetsamEvent alloc] init];
    if (x != nil) {
        x.appVersion = appVersion;
        x.runningTime = runningTime;
        x.jetsamDate = jetsamDate;
    }

    return x;
}

#pragma mark - Equality

- (BOOL)isEqualToJetsamEvent:(JetsamEvent*)jetsam {
    BOOL appVersionEqual =
        (self.appVersion == nil && jetsam.appVersion == nil) ||
        [jetsam.appVersion isEqualToString:self.appVersion];

    return
        appVersionEqual &&
        jetsam.runningTime == self.runningTime &&
        jetsam.jetsamDate == self.jetsamDate;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[JetsamEvent class]]) {
        return NO;
    }

    return [self isEqualToJetsamEvent:(JetsamEvent*)object];
}

#pragma mark - NSCoding protocol implementation

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInteger:JetsamEventArchiveVersion1
                  forKey:JetsamEventArchiveVersionIntegerCoderKey];
    [coder encodeObject:self.appVersion
                 forKey:JetsamEventAppVersionCoderKey];
    [coder encodeDouble:self.runningTime
                 forKey:JetsamEventRunningTimeCoderKey];
    [coder encodeDouble:self.jetsamDate
                 forKey:JetsamEventDateCoderKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.appVersion = [coder decodeObjectOfClass:[NSString class]
                                              forKey:JetsamEventAppVersionCoderKey];
        self.runningTime = [coder decodeDoubleForKey:JetsamEventRunningTimeCoderKey];
        self.jetsamDate = [coder decodeDoubleForKey:JetsamEventDateCoderKey];
    }
    return self;
}

#pragma mark - NSSecureCoding protocol implementation

+ (BOOL)supportsSecureCoding {
   return YES;
}

#pragma mark - JSONCodable protocol implementation

- (NSDictionary*)jsonCodableDictionary {

    NSMutableDictionary *o = [[NSMutableDictionary alloc] init];

    // Note: reuses NSCoding keys
    [o setObject:self.appVersion forKey:JetsamEventAppVersionCoderKey];
    [o setObject:[NSNumber numberWithDouble:self.runningTime] forKey:JetsamEventRunningTimeCoderKey];
    [o setObject:[NSNumber numberWithDouble:self.jetsamDate] forKey:JetsamEventDateCoderKey];

    return o;
}

+ (nonnull id)jsonCodableObjectFromJSONDictionary:(nonnull NSDictionary *)dict
                                            error:(NSError *_Nullable *)outError {
    *outError = nil;

    id appVersion = [dict objectForKey:JetsamEventAppVersionCoderKey];
    if (appVersion == nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:@"Value for app version nil"];
        return nil;
    }
    if (![appVersion isKindOfClass:[NSString class]]) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:[NSString
                                              stringWithFormat:
                                              @"Unexpected class for app version: %@", [appVersion class]]];
    }

    id runningTime = [dict objectForKey:JetsamEventRunningTimeCoderKey];
    if (runningTime == nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:@"Value for running time nil"];
        return nil;
    }
    if (![runningTime isKindOfClass:[NSNumber class]]) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:[NSString
                                              stringWithFormat:
                                              @"Unexpected class for running time: %@", [runningTime class]]];
    }

    id jetsamDate = [dict objectForKey:JetsamEventDateCoderKey];
    if (jetsamDate == nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:@"Value for jetsam date nil"];
        return nil;
    }
    if (![jetsamDate isKindOfClass:[NSNumber class]]) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:[NSString
                                              stringWithFormat:
                                              @"Unexpected class for jetsam date: %@", [jetsamDate class]]];
    }

    JetsamEvent *event = [JetsamEvent jetsamEventWithAppVersion:(NSString*)appVersion
                                                    runningTime:((NSNumber*)runningTime).doubleValue
                                                     jetsamDate:((NSNumber*)jetsamDate).doubleValue];

    return event;
}

@end
