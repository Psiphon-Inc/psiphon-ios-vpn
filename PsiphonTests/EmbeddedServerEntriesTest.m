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
#import "EmbeddedServerEntries.h"

@interface EmbeddedServerEntriesTest : XCTestCase

@end

@implementation EmbeddedServerEntriesTest

/// Test decoding server entries embedded in the app target.
- (void)testEgressRegionsFromFile {
    [self egressRegionsFromFile];
}

/// Test performance of decoding server entries embedded in the app target.
- (void)testPerformanceEgressRegionsFromFile {
    [self measureBlock:^{
        [self egressRegionsFromFile];
    }];
}

- (void)testEgressRegionsFromNonExistantFile {
    NSError *e;
    NSSet *embeddedEgressRegions =
        [EmbeddedServerEntries egressRegionsFromFile:@"non_existant_file" error:&e];
    XCTAssertNotNil(e);
    XCTAssertEqual(e.code, EmbeddedServerEntriesErrorFileError);
    XCTAssertNotNil(embeddedEgressRegions);
    XCTAssertTrue([embeddedEgressRegions count] == 0);
}

- (void)testEgressRegionsFromWrongFile {
    NSError *e;
    NSSet *embeddedEgressRegions =
        [EmbeddedServerEntries egressRegionsFromFile:[EmbeddedServerEntriesTest createFileWithRandomData]
                                               error:&e];
    XCTAssertNotNil(e);
    XCTAssertEqual(e.code, EmbeddedServerEntriesErrorDecodingError);
    XCTAssertNotNil(embeddedEgressRegions);
    XCTAssertTrue([embeddedEgressRegions count] == 0);
}

#pragma mark - Helpers

- (void)egressRegionsFromFile {
    NSError *e;
    NSSet *embeddedEgressRegions =
        [EmbeddedServerEntries egressRegionsFromFile:[EmbeddedServerEntriesTest embeddedServerEntriesPath]
                                               error:&e];
    XCTAssertNil(e);
    XCTAssertNotNil(embeddedEgressRegions);
    XCTAssertTrue([embeddedEgressRegions count] > 0);
}

+ (NSString*)embeddedServerEntriesPath {
    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    return [[testBundle resourcePath] stringByAppendingPathComponent:@"embedded_server_entries"];
}

+ (NSString*)createFileWithRandomData {
    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *newFilePath =
        [[testBundle resourcePath] stringByAppendingPathComponent:@"invalid_embedded_server_entries"];

    [[NSFileManager defaultManager] createFileAtPath:newFilePath
                                            contents:[EmbeddedServerEntriesTest randomData] attributes:nil];
    return newFilePath;
}

+ (NSData*)randomData {
    int capacity = 1048576; // 1 MB
    NSMutableData *data = [NSMutableData dataWithCapacity:capacity];
    for (int i = 0; i < capacity/4; i++) {
        u_int32_t randomBits = arc4random();
        [data appendBytes:(void*)&randomBits length:4];
    }
    return data;
}

@end
