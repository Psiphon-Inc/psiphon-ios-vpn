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

#import "Archiver.h"
#import "NSError+Convenience.h"

NSErrorDomain _Nonnull const ArchiverErrorDomain = @"ArchiverErrorDomain";

@implementation Archiver

+ (NSData *)archiveObject:(id<NSCoding, NSSecureCoding>)object
                    error:(NSError * _Nullable *)outError {

    NSData *data;

    if (@available(iOS 11.0, *)) {
        NSError *err;
        data = [NSKeyedArchiver archivedDataWithRootObject:object
                                     requiringSecureCoding:YES
                                                     error:&err];
        if (err) {
            *outError = [NSError errorWithDomain:ArchiverErrorDomain
                                            code:ArchiverErrorArchiveFailed
                             withUnderlyingError:err];
            return nil;
        }
    } else {
        data = [NSKeyedArchiver archivedDataWithRootObject:object];
        if (data == nil) {
            *outError = [NSError errorWithDomain:ArchiverErrorDomain
                                            code:ArchiverErrorArchiveFailed
                         andLocalizedDescription:@"Archived data is nil"];
            return nil;
        }
    }

    return data;
}

+ (id)unarchiveObjectWithData:(NSData*)data
                        error:(NSError * _Nullable *)outError {
    *outError = nil;

    id object;
    if (@available(iOS 11.0, *)) {
        NSError *err;
        object = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:data
                                                              error:&err];
        if (err) {
            *outError = [NSError errorWithDomain:ArchiverErrorDomain
                                            code:ArchiverErrorUnarchiveFailed
                             withUnderlyingError:err];
        }
    } else {
        // Raises an NSInvalidArgumentException if data is not a valid archive.
        @try {
            object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        }
        @catch (NSException *exception) {
            *outError = [NSError errorWithDomain:ArchiverErrorDomain
                                            code:ArchiverErrorUnarchiveFailed
                         andLocalizedDescription:[NSString stringWithFormat:@"Exception unarchiving data: %@", exception.description]];
            return nil;
        }
        @finally {}
    }

    return object;
}

@end
