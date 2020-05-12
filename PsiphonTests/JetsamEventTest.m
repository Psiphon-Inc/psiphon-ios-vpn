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
#import "Archiver.h"
#import "JetsamEvent.h"

@interface JetsamEventTest : XCTestCase

@end

@implementation JetsamEventTest

#pragma mark - NSCoding protocol implementation tests

- (void)testNSCoding {
    JetsamEvent *jetsam = [JetsamEvent jetsamEventWithAppVersion:@"1"
                                                     runningTime:10
                                                      jetsamDate:[NSDate.date timeIntervalSince1970]];

    // Encode

    NSError *err;
    NSData *data = [Archiver archiveObject:jetsam error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Decode

    JetsamEvent *decodedJetsam = [Archiver unarchiveObjectWithData:data error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Compare
    XCTAssertNotNil(decodedJetsam);
    XCTAssertTrue([jetsam isEqual:decodedJetsam]);
}

#pragma mark - JSONCodable protocol implementation tests

- (void)testJSONCodable {
    JetsamEvent *jetsam = [JetsamEvent jetsamEventWithAppVersion:@"1"
                                                     runningTime:10
                                                      jetsamDate:[NSDate.date timeIntervalSince1970]];

    // Encode

    NSError *err;
    NSData *data = [JSONCodable jsonCodableEncodeObject:jetsam
                                                  error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Decode

    JetsamEvent *decodedJetsam = [JSONCodable jsonCodableDecodeObjectofClass:[JetsamEvent class]
                                                                        data:data
                                                                       error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
    }

    // Compare
    XCTAssertNotNil(decodedJetsam);
    XCTAssertTrue([jetsam isEqual:decodedJetsam]);
}


@end
