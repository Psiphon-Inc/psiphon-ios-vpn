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
#import "RotatingFile.h"

@interface RotatingFileTest : XCTestCase

@end

@implementation RotatingFileTest

/// Test writing the file until it rotates. Verify data.
- (void)testFileRotation {

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSURL *dir = [testBundle resourceURL];
    if (dir == nil) {
        XCTFail(@"Failed test bundle resource URL");
        return;
    }

    NSString *filePath = [dir URLByAppendingPathComponent:@"rotating_file"].path;
    NSString *olderFilePath = [dir URLByAppendingPathComponent:@"rotating_file.old"].path;

    // Clean up files from previous run
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:filePath error:nil];
    [fileManager removeItemAtPath:olderFilePath error:nil];

    NSError *err;
    RotatingFile *rotatingFile = [[RotatingFile alloc] initWithFilepath:filePath
                                                          olderFilepath:olderFilePath
                                                       maxFilesizeBytes:256
                                                                  error:&err];

    if (err != nil) {
        XCTFail(@"Init should succeed: %@", err);
        return;
    }

    // Write the file past max size
    void *random_bytes = (void*)malloc(257);
    NSData *bytes = [NSData dataWithBytes:random_bytes length:257];
    free(random_bytes);
    {
        [rotatingFile writeData:bytes error:&err];
        if (err != nil) {
            XCTFail(@"Write should succeed: %@", err);
            return;
        }

        XCTAssertTrue([fileManager fileExistsAtPath:filePath]);
        XCTAssertFalse([fileManager fileExistsAtPath:olderFilePath]);

        unsigned long long file_size = [[fileManager attributesOfItemAtPath:filePath error:&err] fileSize];
        if (err != nil) {
            XCTFail("Failed to get file size: %@", err);
            return;
        }
        XCTAssertEqual(file_size, 257);
    }

    // Next write will cause rotation.
    void *next_random_bytes = (void*)malloc(256);
    free(next_random_bytes);
    NSData *nextBytes = [NSData dataWithBytes:next_random_bytes length:256];
    {
        [rotatingFile writeData:nextBytes error:&err];
        if (err != nil) {
            XCTFail(@"Write should succeed: %@", err);
            return;
        }

        XCTAssertTrue([fileManager fileExistsAtPath:filePath]);
        XCTAssertTrue([fileManager fileExistsAtPath:olderFilePath]);

        unsigned long long file_size = [[fileManager attributesOfItemAtPath:filePath error:&err] fileSize];
        if (err != nil) {
            XCTFail("Failed to get file size: %@", err);
            return;
        }
        XCTAssertEqual(file_size, 256);

        unsigned long long old_file_size = [[fileManager attributesOfItemAtPath:olderFilePath error:&err] fileSize];
        if (err != nil) {
            XCTFail("Failed to get file size: %@", err);
            return;
        }
        XCTAssertEqual(old_file_size, 257);
    }

    // Check file contents
    NSData *filePathData = [NSData dataWithContentsOfFile:filePath];
    NSData *olderfilePathData = [NSData dataWithContentsOfFile:olderFilePath];

    XCTAssertTrue([filePathData isEqual:nextBytes]);
    XCTAssertTrue([olderfilePathData isEqual:bytes]);
}

@end
