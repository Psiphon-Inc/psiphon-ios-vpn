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
#import "ExtensionContainerFile.h"

@interface ExtensionContainerFileTest : XCTestCase

@end

@implementation ExtensionContainerFileTest

/// Test writing/reading the rotated files and persisting/restoring the registry state.
- (void)testWriteThenReadBack {

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSURL *dir = [testBundle resourceURL];
    if (dir == nil) {
        XCTFail(@"Failed test bundle resource URL");
        return;
    }

    NSString *filePath = [dir URLByAppendingPathComponent:@"file"].path;
    NSString *olderFilePath = [dir URLByAppendingPathComponent:@"file.1"].path;
    NSString *registryFilePath = [dir URLByAppendingPathComponent:@"registry"].path;

    // cleanup previous run
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:filePath error:nil];
    [fileManager removeItemAtPath:olderFilePath error:nil];
    [fileManager removeItemAtPath:registryFilePath error:nil];

    NSError *err;
    ExtensionWriterRotatedFile *ext =
      [[ExtensionWriterRotatedFile alloc] initWithFilepath:filePath
                                             olderFilepath:olderFilePath
                                          maxFilesizeBytes:8
                                                     error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    // Due to the 8 byte max filesize each two entries will comprise their own file.
    // The file comprised of the first two entries will be rotated and then deleted after the
    // writes have completed.
    // It is expected that the lines are read back in the order that they are written. The rotated
    // file is read first.
    NSArray<NSString*>* lines = @[@"abcd", @"efgh", @"ijkl", @"mnop", @"qrst", @"uvwx"];
    NSArray<NSString*>* expectedLines = @[@"ijkl", @"mnop", @"qrst", @"uvwx"];

    for (NSString *line in lines) {
        [ext writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSASCIIStringEncoding]
                 error:&err];
        if (err != nil) {
            XCTFail(@"Unexpected error: %@", err);
            return;
        }
    }

    ContainerReaderRotatedFile *cont =
      [[ContainerReaderRotatedFile alloc] initWithFilepath:filePath
                                             olderFilepath:olderFilePath
                                          registryFilepath:registryFilePath
                                             readChunkSize:64
                                                     error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    NSMutableArray<NSString*>* readLines = [[NSMutableArray alloc] init];

    while (true) {
        NSString *line = [cont readLineWithError:&err];
        if (err != nil) {
            XCTFail(@"Unexpected error: %@", err);
            return;
        }
        if (line == nil) {
            break;
        }
        [readLines addObject:line];
    }

    if (![readLines isEqualToArray:expectedLines]) {
        XCTFail(@"%@ is not equal to expected lines %@", readLines, expectedLines);
        return;
    }

    [cont persistRegistry:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    // Confirm next read returns nothing.

    cont =
        [[ContainerReaderRotatedFile alloc] initWithFilepath:filePath
                                               olderFilepath:olderFilePath
                                            registryFilepath:registryFilePath
                                               readChunkSize:64
                                                       error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    NSString *line = [cont readLineWithError:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }
    XCTAssertNil(line);

    [cont persistRegistry:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    // Write some more lines and validate that the registry has been persisted and restored
    // successfully.

    lines = @[@"1234"];
    // Expect to only read back the latest lines since the previous lines have been read and this
    // was persisted in the registry.
    expectedLines = @[@"1234"];

    for (NSString *line in lines) {
        [ext writeData:[[line stringByAppendingString:@"\n"]
                        dataUsingEncoding:NSASCIIStringEncoding]
                 error:&err];
        if (err != nil) {
            XCTFail(@"Unexpected error: %@", err);
            return;
        }
    }

    cont =
      [[ContainerReaderRotatedFile alloc] initWithFilepath:filePath
                                           olderFilepath:olderFilePath
                                        registryFilepath:registryFilePath
                                           readChunkSize:1
                                                   error:&err];

    readLines = [[NSMutableArray alloc] init]; // reset

    while (true) {
        NSString *line = [cont readLineWithError:&err];
        if (err != nil) {
            XCTFail(@"Unexpected error: %@", err);
            return;
        }
        if (line == nil) {
            break;
        }
        [readLines addObject:line];
    }

    if (![readLines isEqualToArray:expectedLines]) {
        XCTFail(@"%@ is not equal to expected lines %@", readLines, expectedLines);
        return;
    }

    [cont persistRegistry:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    // Write another line which will not cause a file rotation.
    // After this we can check if the offset was restored successfully.

    lines = @[@"5678"];
    // Expect to only read back the latest lines since the previous lines have been read and this
    // was persisted in the registry.
    expectedLines = @[@"5678"];

    for (NSString *line in lines) {
        [ext writeData:[[line stringByAppendingString:@"\n"]
                        dataUsingEncoding:NSASCIIStringEncoding]
                 error:&err];
        if (err != nil) {
            XCTFail(@"Unexpected error: %@", err);
            return;
        }
    }

    cont =
      [[ContainerReaderRotatedFile alloc] initWithFilepath:filePath
                                           olderFilepath:olderFilePath
                                        registryFilepath:registryFilePath
                                           readChunkSize:1
                                                   error:&err];

    readLines = [[NSMutableArray alloc] init]; // reset

    while (true) {
        NSString *line = [cont readLineWithError:&err];
        if (err != nil) {
            XCTFail(@"Unexpected error: %@", err);
            return;
        }
        if (line == nil) {
            break;
        }
        [readLines addObject:line];
    }

    if (![readLines isEqualToArray:expectedLines]) {
        XCTFail(@"%@ is not equal to expected lines %@", readLines, expectedLines);
        return;
    }

    [cont persistRegistry:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    // Confirm the offset was successfully restored and the next read returns nothing.

    cont =
        [[ContainerReaderRotatedFile alloc] initWithFilepath:filePath
                                               olderFilepath:olderFilePath
                                            registryFilepath:registryFilePath
                                               readChunkSize:64
                                                       error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    line = [cont readLineWithError:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }
    XCTAssertNil(line);

    [cont persistRegistry:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }
}

/// Test persisting and restoring the registry when the delimted file reader has buffered data that has not yet been returned. The offset
/// in the registry must track the amount of data returned from the reader as opposed to the amount of data the reader has read from the
/// file handle. Otherwise reads may erroneously start mid-line when the registry is restored.
- (void)testPartialReadBack {

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSURL *dir = [testBundle resourceURL];
    if (dir == nil) {
        XCTFail(@"Failed test bundle resource URL");
        return;
    }

    NSString *filePath = [dir URLByAppendingPathComponent:@"file"].path;
    NSString *olderFilePath = [dir URLByAppendingPathComponent:@"file.1"].path;
    NSString *registryFilePath = [dir URLByAppendingPathComponent:@"registry"].path;

    // cleanup previous run
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:filePath error:nil];
    [fileManager removeItemAtPath:olderFilePath error:nil];
    [fileManager removeItemAtPath:registryFilePath error:nil];

    NSError *err;
    ExtensionWriterRotatedFile *ext =
     [[ExtensionWriterRotatedFile alloc] initWithFilepath:filePath
                                            olderFilepath:olderFilePath
                                         maxFilesizeBytes:8
                                                    error:&err];
    if (err != nil) {
       XCTFail(@"Unexpected error: %@", err);
       return;
    }

    NSArray<NSString*>* lines = @[@"abcd", @"efgh"];
    for (NSString *line in lines) {
       [ext writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSASCIIStringEncoding]
                error:&err];
       if (err != nil) {
           XCTFail(@"Unexpected error: %@", err);
           return;
       }
    }

    ContainerReaderRotatedFile *cont =
     [[ContainerReaderRotatedFile alloc] initWithFilepath:filePath
                                            olderFilepath:olderFilePath
                                         registryFilepath:registryFilePath
                                            readChunkSize:4
                                                    error:&err];
    if (err != nil) {
       XCTFail(@"Unexpected error: %@", err);
       return;
    }

    NSString *line = [cont readLineWithError:&err];
    if (err != nil) {
       XCTFail(@"Unexpected error: %@", err);
       return;
    }
    NSLog(@"%@", line);

    [cont persistRegistry:&err];
    if (err != nil) {
       XCTFail(@"Unexpected error: %@", err);
       return;
    }

    NSLog(@"done");

    // Confirm next read returns nothing.

    cont =
        [[ContainerReaderRotatedFile alloc] initWithFilepath:filePath
                                               olderFilepath:olderFilePath
                                            registryFilepath:registryFilePath
                                               readChunkSize:64
                                                       error:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }

    line = [cont readLineWithError:&err];
    if (err != nil) {
        XCTFail(@"Unexpected error: %@", err);
        return;
    }
    if (![line isEqualToString:@"efgh"]) {
        XCTFail(@"Unexpected line: %@", line);
        return;
    }
}

@end
