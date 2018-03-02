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

#import "EmbeddedServerEntries.h"
#import "EmbeddedServerEntriesHelpers.h"
#import "Logging.h"
#import "PsiFeedbackLogger.h"

#define kEmbeddedServerEntryRegionJsonKey @"region"

@implementation EmbeddedServerEntries

+ (NSArray*)egressRegionsFromFile:(NSString*)filePath {
    NSMutableOrderedSet *egressRegions = [[NSMutableOrderedSet alloc] init];

    FILE * fp;
    char * line = NULL;
    size_t len = 0;
    ssize_t nread;

    fp = fopen([filePath UTF8String], "r");
    if (fp == NULL) {
        [PsiFeedbackLogger error:@"Error failed to open embedded server entry file at path (%@).", filePath];
        return nil;
    }

    errno = 0;
    unsigned long line_number = 1;

    while ((nread = getline(&line, &len, fp)) != -1) {
        // Drop carriage return and newline if present.
        // This is done by moving the null terminator and
        // not reallocing.
        drop_newline_and_carriage_return(line);

        errno = 0;
        char *decoded = hex_decode(line);
        if (decoded == NULL) {
            [PsiFeedbackLogger error:@"Error failed to hex decode line (%lu) in embedded server entries file at path (#%@): %s.", line_number, filePath, strerror(errno)];
            break;
        }

        char *json = server_entry_json(decoded);
        if (json == NULL) {
            [PsiFeedbackLogger error:@"Error failed to find server entry in hex decoded line (#%lu) in embedded server entries file at path (%@).", line_number, filePath];
            free(decoded);
            break;
        }

        NSData *jsonData = [NSData dataWithBytes:json length:strlen(json)];
        free(decoded);
        if (jsonData == nil) {
            [PsiFeedbackLogger error:@"Error failed to convert embedded server entry json data from line (#%lu) to NSData.", line_number];
            break;
        }

        NSError *error = nil;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&error];
        if (error != nil) {
            [PsiFeedbackLogger error:@"Error failed to serialize json object from decoded server entry on line (#%lu): %@.", line_number, error];
            break;
        }

        id regionObject = jsonObject[kEmbeddedServerEntryRegionJsonKey];
        if (regionObject == nil) {
            [PsiFeedbackLogger error:@"Error failed to find region key (%@) in embedded server entry json on line (#%lu).", kEmbeddedServerEntryRegionJsonKey, line_number];
            break;
        } else if ([regionObject isKindOfClass:[NSString class]]) {
            [egressRegions addObject:(NSString*)regionObject];
        } else {
            [PsiFeedbackLogger error:@"Error region in embedded server entry on line (#%lu) is not NSString but %@.", line_number, [regionObject class]];
            break;
        }

        line_number++;
    }

    if (nread == -1 && errno != 0 && ferror(fp) != 0) {
        [PsiFeedbackLogger error:@"Error reading embedded server entries file at path (%@): %s.", filePath, strerror(errno)];
    }

    errno = 0;
    int ret = fclose(fp);
    if (ret != 0) {
        [PsiFeedbackLogger error:@"Error closing file stream for embedded server entries file at path (%@): %s.", filePath, strerror(errno)];
    }

    if (line != NULL) {
        free(line);
    }

    return [egressRegions array];
}

@end
