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

#import "JSONCodable.h"
#import "NSError+Convenience.h"

NSErrorDomain _Nonnull const JSONCodableErrorDomain = @"JSONCodableErrorDomain";

@implementation JSONCodable

+ (NSData *_Nullable)jsonCodableEncodeObject:(id<JSONCodable>)object error:(NSError *_Nullable *)outError {

    *outError = nil;

    NSDictionary *o = [object jsonCodableDictionary];
    if (o == nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorEncodingFailed
                     andLocalizedDescription:@"JSON codable dict nil"];
        return nil;
    }

    if (![NSJSONSerialization isValidJSONObject:o]) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorEncodingFailed
                     andLocalizedDescription:@"JSON codable dict invalid JSON object"];
        return nil;
    }

    NSError *err;
    NSData *data = [NSJSONSerialization dataWithJSONObject:o
                                                   options:kNilOptions
                                                     error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorEncodingFailed
                     andLocalizedDescription:@"Error encoding object"
                         withUnderlyingError:err];
        return nil;
    }
    if (data == nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorEncodingFailed
                     andLocalizedDescription:@"Encoded data nil"];
        return nil;
    }

    return data;
}

+ (id _Nullable)jsonCodableDecodeObjectofClass:(Class<JSONCodable>)aClass
                                          data:(NSData*)data
                                         error:(NSError *_Nullable *)outError {

    *outError = nil;

    NSError *err;
    id dict = [NSJSONSerialization JSONObjectWithData:data
                                                options:kNilOptions
                                                  error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:@"Error decoding object dict"
                         withUnderlyingError:err];
        return nil;
    }
    if (dict == nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:@"Decoded data nil"];
        return nil;
    }
    if (![dict isKindOfClass:[NSDictionary class]]) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:[NSString stringWithFormat:
                                              @"Decoded data not dict but: %@", [dict class]]];
        return nil;
    }

    id object = [aClass jsonCodableObjectFromJSONDictionary:dict
                                                      error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:JSONCodableErrorDomain
                                        code:JSONCodableErrorDecodingFailed
                     andLocalizedDescription:@"Error decoding object from dict"
                            withUnderlyingError:err];
        return nil;
    }

    return object;
}

@end
