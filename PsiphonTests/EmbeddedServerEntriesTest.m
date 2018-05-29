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

#import <XCTest/XCTest.h>
#import "EmbeddedServerEntries.h"
#import "PsiphonConfigReader.h"
#import "SharedConstants.h"

@interface EmbeddedServerEntriesTest : XCTestCase

@end

@implementation EmbeddedServerEntriesTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testEgressRegionsFromFile {
    [self egressRegionsFromFile];
}

- (void)testPerformanceEgressRegionsFromFile {
    [self measureBlock:^{
        [self egressRegionsFromFile];
    }];
}

- (void)testEgressRegionsFromNonExistantFile {
    NSArray *embeddedEgressRegions = [EmbeddedServerEntries egressRegionsFromFile:@"non_existant_file"];
    XCTAssertTrue([embeddedEgressRegions count] == 0);
}

- (void)testEgressRegionsFromWrongFile {
    NSArray *embeddedEgressRegions = [EmbeddedServerEntries egressRegionsFromFile:PsiphonConfigReader.psiphonConfigPath];
    XCTAssertTrue([embeddedEgressRegions count] == 0);
}

#pragma mark - Helpers

- (void)egressRegionsFromFile {
    NSArray *embeddedEgressRegions = [EmbeddedServerEntries egressRegionsFromFile:PsiphonConfigReader.embeddedServerEntriesPath];
    XCTAssertTrue([embeddedEgressRegions count] > 0);
}

@end
