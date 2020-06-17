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

FOUNDATION_EXPORT NSErrorDomain const EmbeddedServerEntriesErrorDomain;

typedef NS_ERROR_ENUM(EmbeddedServerEntriesErrorDomain, EmbeddedServerEntriesErrorDomainErrorCode) {
    EmbeddedServerEntriesErrorFileError = 1,
    EmbeddedServerEntriesErrorDecodingError = 2
};

@interface EmbeddedServerEntries : NSObject

/// Decode embedded server entries file and return set of all egress regions available in the decoded entries.
/// @param filePath Path to embedded server entries file.
/// @param outError Non-nil if an error occurs. If some server entries were successfully decoded before the error occured, then they
/// will still be returned.
/// @return Set of all egress regions with a corresponding server entry.
+ (NSSet*)egressRegionsFromFile:(NSString*)filePath error:(NSError * _Nullable *)outError;

@end

NS_ASSUME_NONNULL_END
