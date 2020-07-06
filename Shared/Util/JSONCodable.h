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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const JSONCodableErrorDomain;

typedef NS_ERROR_ENUM(JSONCodableErrorDomain, JSONCodableErrorCode) {
    JSONCodableErrorEncodingFailed = 1,
    JSONCodableErrorDecodingFailed = 2,
};

/// Protocol for encoding and decoding objects which uses a NSDictionary as an intermediate representation.
/// The NSDictionary must be valid for JSON de-/serialization with NSJSONSerialization (see NSJSONSerialization:isValidJSONObject:).
/// @note This protocol is meant for use with the JSONCodable class to facilitate JSON de-/serialization.
@protocol JSONCodable

/// Return a dictionary which is valid for JSON de-/serialization with NSJSONSerialization.
- (NSDictionary*)jsonCodableDictionary;

/// Recreate object from JSON dictionary.
/// @param dict Dictionary valid for JSON de-/serialization with NSJSONSerialization (see NSJSONSerialization:isValidJSONObject:).
/// @param outError If non-nill on return, then initialization failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
+ (id)jsonCodableObjectFromJSONDictionary:(NSDictionary*)dict
                                    error:(NSError *_Nullable *)outError;

@end

/// Class which facilitates encoding and decoding JSONCodable classes with JSON as the intermediate representation.
@interface JSONCodable : NSObject

/// Encode object to JSON data.
/// @param object Object to encode.
/// @param outError If non-nill on return, then initialization failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
+ (NSData *_Nullable)jsonCodableEncodeObject:(id<JSONCodable>)object
                                       error:(NSError *_Nullable *)outError;

/// Decode object from JSON data.
/// @param aClass JSONCodable class to decode.
/// @param data Data to decode.
/// @param outError If non-nill on return, then initialization failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
+ (id _Nullable)jsonCodableDecodeObjectofClass:(Class<JSONCodable>)aClass
                                          data:(NSData*)data
                                         error:(NSError *_Nullable *)outError;

@end

NS_ASSUME_NONNULL_END
