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

#import "PsiphonClientCommonLibraryConstants.h"
#import "PsiphonClientCommonLibraryHelpers.h"

@implementation PsiphonClientCommonLibraryHelpers

+ (NSBundle*)commonLibraryBundle {
    NSBundle *frameworkBundle = [NSBundle bundleForClass:self.classForCoder];
    NSString *bundlePath = [frameworkBundle pathForResource:kPsiphonClientCommonLibraryBundleName ofType:@"bundle"];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    return bundle;
}

// From http://blog.flaviocaetano.com/post/cocoapods-and-resource_bundles/
+ (UIImage*)imageFromCommonLibraryNamed:(NSString*)imageName {
    return [UIImage imageNamed:imageName inBundle:[PsiphonClientCommonLibraryHelpers commonLibraryBundle] compatibleWithTraitCollection:nil];
}

// See header for comment.
+ (void)initializeDefaultsForPlistsFromRoot:(NSString* _Nonnull)rootPlist {
    // Set up some state, then call through to a recursive helper.
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *fileHistory = [[NSMutableArray alloc] init];
    [PsiphonClientCommonLibraryHelpers initializeDefaultsForPlist:rootPlist
                                                  withFileHistory:fileHistory
                                                  andUserDefaults:userDefaults];
    [userDefaults synchronize];
}

/*!
 Recursive helper for initializeDefaultsForPlistsFromRoot.
 */
+ (void)initializeDefaultsForPlist:(NSString* _Nullable)plistName
                   withFileHistory:(NSMutableArray* _Nonnull)fileHistory
                   andUserDefaults:(NSUserDefaults* _Nonnull)userDefaults {
    if (!plistName) {
        return;
    }

    if ([plistName hasSuffix:@".plist"]) {
        NSLog(@"initializeDefaultsForPlist error: Do not include .plist extension: %@", plistName);
        abort();
    }

    // Prevent cycles (infinite recursion) by keeping track of which plists we have
    // already processed.
    NSInteger fileIndex = [fileHistory indexOfObject:plistName];
    if (fileIndex != NSNotFound){
        return;
    }
    [fileHistory addObject:plistName];

    // We'll look for the plist first in the main bundle...
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:plistName ofType:@"plist" inDirectory:@"InAppSettings.bundle"];
    NSDictionary *settingsDictionary = [NSDictionary dictionaryWithContentsOfFile:plistPath];

    // ...and then in the PsiphonClientCommonLibrary bundle.
    if (settingsDictionary == nil) {
        plistPath = [[PsiphonClientCommonLibraryHelpers commonLibraryBundle] pathForResource:plistName ofType:@"plist"];
        settingsDictionary = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    }

    if (!settingsDictionary) {
        NSLog(@"initializeDefaultsForPlist error: Failed to find plist: %@", plistName);
        abort();
    }

    for (NSDictionary *pref in settingsDictionary[@"PreferenceSpecifiers"]) {
        NSString *key = pref[@"Key"];
        if (key != nil && [userDefaults objectForKey:key] == NULL) {
            NSObject *val = pref[@"DefaultValue"];
            if (val != nil)
            {
                [userDefaults setObject:val forKey:key];
#ifdef TRACE
                NSLog(@"initialized default preference for %@ to %@", key, val);
#endif
            }
        }

        NSString* type = pref[@"Type"];
        if (([type isEqualToString:@"PSChildPaneSpecifier"] || [type isEqualToString:@"IASKCustomViewSpecifier"]) &&
            pref[@"File"]) {
            // Make a recursive call.
            [PsiphonClientCommonLibraryHelpers initializeDefaultsForPlist:pref[@"File"]
                                                          withFileHistory:fileHistory
                                                          andUserDefaults:userDefaults];
        }
    }
}

+ (NSString * _Nullable)getPsiphonBundledConfig {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *bundledConfigPath = [[[NSBundle mainBundle] resourcePath]
                                   stringByAppendingPathComponent:@"psiphon_config"];

    if (![fileManager fileExistsAtPath:bundledConfigPath]) {
        NSLog(@"Config file not found for feedback upload.");
        return @"";
    }

    // Read in psiphon_config JSON
    NSData *jsonData = [fileManager contentsAtPath:bundledConfigPath];
    NSError *err = nil;
    NSDictionary *readOnly = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&err];

    if (err) {
        NSLog(@"Failed to parse config JSON for feedback upload: %@", err.description);
        return @"";
    }

    NSMutableDictionary *mutableConfigCopy = [readOnly mutableCopy];
    jsonData  = [NSJSONSerialization dataWithJSONObject:mutableConfigCopy
                                                options:0 error:&err];

    if (err) {
        NSLog(@"Failed to create JSON data from config object for feedback upload: %@", err.description);
        abort();
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

+ (BOOL)unsupportedCharactersForFont:(NSString* _Nonnull)font withString:(NSString* _Nonnull)string {
    for (NSUInteger charIdx = 0; charIdx < string.length; charIdx++) {
        NSString *character = [NSString stringWithFormat:@"%C", [string characterAtIndex:charIdx]];
        // TODO: need to enumerate a longer list of special characters for this to be more correct.
        if ([character isEqualToString:@" "]) {
            // Skip special characters
            continue;
        }
        CGFontRef cgFont = CGFontCreateWithFontName((__bridge CFStringRef)font);
        BOOL unsupported = (CGFontGetGlyphWithGlyphName(cgFont,  (__bridge CFStringRef)character) == 0);
        CGFontRelease(cgFont);
        if (unsupported) {
            return YES;
        }
    }
    return NO;
}

// Convert json string to dictionary
+ (NSDictionary*)jsonToDictionary:(NSString*)jsonString {
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *e = nil;

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&e];

    if (e) {
        return nil;
    }

    return json;
}

@end
