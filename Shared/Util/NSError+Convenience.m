/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "NSError+Convenience.h"


@implementation NSError (Convenience)

+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code {
    return [NSError errorWithDomain:domain code:code userInfo:nil];
}

+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code andLocalizedDescription:(NSString*)localizedDescription {
    return [NSError errorWithDomain:domain code:code userInfo:@{NSLocalizedDescriptionKey:localizedDescription}];
}

+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code withUnderlyingError:(NSError *)error {
    NSDictionary *errorDict = nil;
    if (error) {
        errorDict = @{NSUnderlyingErrorKey: error};
    }
    return [NSError errorWithDomain:domain code:code userInfo:errorDict];
}

+ (instancetype)errorWithDomain:(NSErrorDomain)domain
                           code:(NSInteger)code
        andLocalizedDescription:(NSString*)localizedDescription
            withUnderlyingError:(NSError *)error {
    NSDictionary *errorDict = nil;
    if (error) {
        errorDict = @{NSLocalizedDescriptionKey: localizedDescription,
                      NSUnderlyingErrorKey: error};
    }
    return [NSError errorWithDomain:domain code:code userInfo:errorDict];
}

- (NSDictionary<NSString *, id> *)jsonSerializableDictionaryRepresentation {
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];

    [d setObject:@(self.code) forKey:@"code"];

    if (self.domain) {
        [d setObject:self.domain forKey:@"domain"];
    }

    if (self.userInfo && [self.userInfo count] > 0) {
        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];

        id localizedDescription = [self.userInfo objectForKey:NSLocalizedDescriptionKey];
        if (localizedDescription && [localizedDescription isKindOfClass:NSString.class]) {
            [userInfo setObject:(NSString*)localizedDescription forKey:@"localized_description"];
        }

        id underlyingError = [self.userInfo objectForKey:NSUnderlyingErrorKey];
        if (underlyingError && [underlyingError isKindOfClass:[NSError class]]) {
            [userInfo setObject:[(NSError*)underlyingError jsonSerializableDictionaryRepresentation] forKey:@"underlying_error"];
        }

        id failureReason = [self.userInfo objectForKey:NSLocalizedFailureReasonErrorKey];
        if (failureReason && [failureReason isKindOfClass:[NSString class]]) {
            [userInfo setObject:(NSString*)failureReason forKey:@"failure_reason"];
        }

        [d setObject:userInfo forKey:@"user_info"];
    }

    return d;
}

@end
