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

#import <XCTest/XCTest.h>
#import "FileRegistry.h"
#import "Archiver.h"

@interface FileRegistryTest : XCTestCase

@end

@implementation FileRegistryTest

#pragma mark - NSCoding protocol implementation tests

- (void)testNSCoding {
    FileRegistry *reg = [[FileRegistry alloc] init];
    [reg setEntry:[FileRegistryEntry fileRegistryEntryWithFilepath:@"/file"
                                              fileSystemFileNumber:1
                                                            offset:0]];
    [reg setEntry:[FileRegistryEntry fileRegistryEntryWithFilepath:@"/file.1"
                                              fileSystemFileNumber:2
                                                            offset:0]];

    // Encode

    NSError *err;
    NSData *data = [Archiver archiveObject:reg error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Decode

    FileRegistry *decodedReg = [Archiver unarchiveObjectWithData:data error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Compare
    XCTAssertNotNil(decodedReg);
    XCTAssertTrue([reg isEqual:decodedReg]);
}

@end
