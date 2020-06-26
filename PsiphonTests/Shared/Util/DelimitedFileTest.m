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

#import "DelimitedFile.h"

@interface DelimitedFileTest : XCTestCase

@end

@implementation DelimitedFileTest

// Read different chunk sizes appropriate for UTF-8 encoding.
- (void)testDifferentChunkSizes {

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSURL *dir = [testBundle resourceURL];
    if (dir == nil) {
        XCTFail(@"Failed test bundle resource URL");
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *filePath = [dir URLByAppendingPathComponent:@"file"].path;
    [fileManager removeItemAtPath:filePath error:nil]; // cleanup previous run

    NSString *s = @"abcdefghikj\nklmnopqrstu\nv12345678\n\n\n\n9\nz";
    NSArray<NSString*>* expectedLines = @[@"abcdefghikj", @"klmnopqrstu", @"v12345678", @"", @"", @"", @"9", @"z"];
    [fileManager createFileAtPath:filePath
                         contents:[s dataUsingEncoding:NSASCIIStringEncoding]
                       attributes:nil];

    // Test different chunk sizes
    NSArray<NSNumber*>* chunkSizes = @[@(1), @(2), @(3), @(7), @(1024)];

    for (NSNumber *chunkSize in chunkSizes) {

        NSError *err;
        DelimitedFile *f = [[DelimitedFile alloc] initWithFilepath:filePath
                                                         chunkSize:[chunkSize unsignedIntValue]
                                                             error:&err];
        if (err != nil) {
            XCTFail(@"Init failed: %@", err);
            return;
        }

        NSMutableArray<NSString*>* readLines = [[NSMutableArray alloc] init];
        NSString *line;
        while ((line = [f readLineWithError:&err])) {
            [readLines addObject:line];
        }
        if (err != nil) {
            XCTFail(@"Chunk size (%@): %@", chunkSize, err);
            return;
        }

        if (![readLines isEqualToArray:expectedLines]) {
            XCTFail(@"Chunk size (%@): %@ is not equal to expected lines %@", chunkSize, readLines, expectedLines);
            return;
        }
    }
}

// Test which closes the file handle between reads.
- (void)testReadError {

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSURL *dir = [testBundle resourceURL];
    if (dir == nil) {
        XCTFail(@"Failed test bundle resource URL");
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *filePath = [dir URLByAppendingPathComponent:@"file"].path;
    [fileManager removeItemAtPath:filePath error:nil]; // cleanup previous run

    NSString *s = @"1234\n5678";
    [fileManager createFileAtPath:filePath
                         contents:[s dataUsingEncoding:NSASCIIStringEncoding]
                       attributes:nil];

    NSError *err;
    DelimitedFile *f = [[DelimitedFile alloc] initWithFilepath:filePath
                                                     chunkSize:4
                                                         error:&err];

    // Do initial read
    NSString *line;
    line = [f readLineWithError:&err];
    if (err != nil) {
        XCTFail(@"%@", err);
        return;
    }

    // Close the file handle
    NSFileHandle *h = [f valueForKey:@"fileHandle"];
    if (h == nil) {
        XCTFail(@"Expected non-nil file handle");
        return;
    }
    [h closeFile];


    while ((line = [f readLineWithError:&err])) {
        XCTFail(@"Next readLineWithError should fail");
        return;
    }
    if (err == nil) {
        XCTFail(@"Expected error");
        return;
    } else {
        XCTAssertEqual(err.domain, DelimitedFileErrorDomain);
        XCTAssertEqual(err.code, DelimitedFileErrorReadFailed);
    }
}

- (void)testFileDoesNotExist {

    NSError *err;
    DelimitedFile *f = [[DelimitedFile alloc] initWithFilepath:@"/does/not/exist"
                                                     chunkSize:4
                                                         error:&err];
    XCTAssertNil(f);
    XCTAssertEqual(err.domain, DelimitedFileErrorDomain);
    XCTAssertEqual(err.code, DelimitedFileErrorFileDoesNotExist);
}

@end
