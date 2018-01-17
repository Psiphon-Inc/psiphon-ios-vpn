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

#import "FileUtils.h"
#import "Logging.h"

@implementation FileUtils

/*!
 * downgradeFileProtectionToNone sets the file protection type of paths to NSFileProtectionNone
 * so that they can be read from or written to at any time.
 * Attributes of exceptions remain untouched.
 * This is required for VPN "Connect On Demand" to work.
 * NOTE: All files containing sensitive information about the user should have file protection level
 *       NSFileProtectionCompleteUntilFirstUserAuthentication at the minimum. This is solely required for protecting
 *       user's data.
 *
 * @param paths List of file or directory paths to downgrade to NSFileProtectionNone.
 * @param exceptions List of file or directory paths to exclude from the downgrade operation.
 * @return TRUE if operation finished successfully, FALSE otherwise.
 */
+ (BOOL)downgradeFileProtectionToNone:(NSArray<NSString *> *)paths withExceptions:(NSArray<NSString *> *)exceptions {
    for (NSString *path in paths) {
        if (![[self class] setFileProtectionNoneRecursively:path withExceptions:exceptions]) {
            return FALSE;
        }
    }
    return TRUE;
}

- (BOOL)setFileProtectionNoneRecursively:(NSString *)path withExceptions:(NSArray<NSString *> *)exceptions{

    NSError *err;
    NSFileManager *fm = [NSFileManager defaultManager];

    BOOL isDirectory;
    if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && ![exceptions containsObject:path]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&err];
        if (err) {
            LOG_ERROR(@"Failed to get file attributes for path (%@) (%@)", path, err);
            return FALSE;
        }

        if (![attrs[NSFileProtectionKey] isEqualToString:NSFileProtectionNone]) {
            [fm setAttributes:@{NSFileProtectionKey: NSFileProtectionNone} ofItemAtPath:path error:&err];
            if (err) {
                LOG_ERROR(@"Failed to set the protection level of dir(%@)", path);
                return FALSE;
            }
        }

        if (isDirectory) {
            NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:path error:&err];
            if (err) {
                LOG_ERROR(@"Failed to get contents of directory (%@) (%@)", path, err);
            }

            for (NSString * item in contents) {
                if (![self setFileProtectionNoneRecursively:[path stringByAppendingPathComponent:item] withExceptions:exceptions]) {
                    return FALSE;
                }
            }
        }
    }

    return TRUE;
}

#if DEBUG
+ (void)listDirectory:(NSString *)dir resource:(NSString *)resource{
    NSError *err;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *desc = [NSMutableArray array];

    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:dir error:&err];

    NSDictionary *dirattrs = [fm attributesOfItemAtPath:dir error:&err];
    LOG_ERROR(@"Dir (%@) attributes:\n\n%@", [dir lastPathComponent], dirattrs[NSFileProtectionKey]);

    if ([files count] > 0) {
        for (NSString *f in files) {
            NSString *file;
            if (![[f stringByDeletingLastPathComponent] isEqualToString:dir]) {
                file = [dir stringByAppendingPathComponent:f];
            } else {
                file = f;
            }

            BOOL isDir;
            [fm fileExistsAtPath:file isDirectory:&isDir];
            NSDictionary *attrs = [fm attributesOfItemAtPath:file error:&err];
            if (err) {
//            LOG_ERROR(@"filepath: %@, %@",file, err);
            }
            [desc addObject:[NSString stringWithFormat:@"%@ : %@ : %@", [file lastPathComponent], (isDir) ? @"dir" : @"file", attrs[NSFileProtectionKey]]];
        }

        LOG_ERROR(@"Resource (%@) Checking files at dir (%@)\n%@", resource, [dir lastPathComponent], desc);
    }
}
#endif

@end
