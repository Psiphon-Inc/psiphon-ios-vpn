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

#import <objc/runtime.h>
#import "PsiphonSettingsViewController.h"
#import "PsiphonClientCommonLibraryHelpers.h"

@implementation UIApplication (UIInterfaceDirection)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        method_exchangeImplementations(class_getInstanceMethod(self, @selector(userInterfaceLayoutDirection)), class_getInstanceMethod(self, @selector(swizzled_userInterfaceLayoutDirection)));
    });
}

- (UIUserInterfaceLayoutDirection) swizzled_userInterfaceLayoutDirection {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString* language = [userDefaults objectForKey:appLanguage];
    if([[language stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""]) {
        language = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
    }

    if (language == nil) {
        return [self swizzled_userInterfaceLayoutDirection];
    }

    return [NSLocale characterDirectionForLanguage:language] == NSLocaleLanguageDirectionRightToLeft ? UIUserInterfaceLayoutDirectionRightToLeft : UIUserInterfaceLayoutDirectionLeftToRight;
}

@end

@implementation UIView (UIInterfaceDirection)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        method_exchangeImplementations(class_getInstanceMethod(self, @selector(semanticContentAttribute)), class_getInstanceMethod(self, @selector(swizzled_semanticContentAttribute)));
    });
}

- (UISemanticContentAttribute) swizzled_semanticContentAttribute {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString* language = [userDefaults objectForKey:appLanguage];
    if([[language stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""]) {
        language = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
    }

    if (language == nil) {
        return [self swizzled_semanticContentAttribute];
    }

    return [NSLocale characterDirectionForLanguage:language] == NSLocaleLanguageDirectionRightToLeft ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
}

@end

// See http://stackoverflow.com/a/20257557
@implementation NSBundle (Language)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        method_exchangeImplementations(class_getInstanceMethod(self, @selector(localizedStringForKey:value:table:)), class_getInstanceMethod(self, @selector(swizzled_localizedStringForKey:value:table:)));
    });
}

- (NSString *)swizzled_localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName NS_FORMAT_ARGUMENT(1);
{
    NSBundle *currentBundle = nil;

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString* language = [userDefaults objectForKey:appLanguage];
    if([[language stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""]) {
        language = nil;
    }

    // Determine if self bundle is one of our own, either main or IASK
    // Override self with main bundle if that's the case
    if ([[self bundlePath] isEqualToString:[[NSBundle mainBundle] bundlePath]] ||
        [[self bundlePath] isEqualToString:([[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"InAppSettings.bundle"])]) {
        currentBundle = [NSBundle mainBundle];
    } else {
        currentBundle = self;
    }

    NSBundle *languageBundle = currentBundle;

    // Use default localization if language is not set
    if (language != nil) {
        languageBundle = [NSBundle bundleWithPath:[currentBundle pathForResource:language ofType:@"lproj"]];
        if (languageBundle == nil) {
            languageBundle = currentBundle;
        }
    }

    NSString* localizedString = [languageBundle swizzled_localizedStringForKey:key value:value table:tableName];

    // If we failed to find the localized string, look in the common library bundle.
    if (language != nil && ![language isEqualToString:@"en"] &&
        (localizedString == nil || [localizedString isEqualToString:value])) {
        languageBundle = [NSBundle bundleWithPath:[[PsiphonClientCommonLibraryHelpers commonLibraryBundle] pathForResource:language ofType:@"lproj"]];
        if (languageBundle != nil) {
            localizedString = [languageBundle swizzled_localizedStringForKey:key value:value table:tableName];
        }
    }

    // If we *still* failed to find the localized string, then maybe it's missing from the .strings file.
    // Fall back to English.
    if ((language == nil || ![language isEqualToString:@"en"]) &&
        (localizedString == nil || [localizedString isEqualToString:value])) {
        languageBundle = [NSBundle bundleWithPath:[currentBundle pathForResource:@"en" ofType:@"lproj"]];
        if (languageBundle != nil) {
            localizedString = [languageBundle swizzled_localizedStringForKey:key value:value table:tableName];
        }
    }

    return localizedString;
}
@end
