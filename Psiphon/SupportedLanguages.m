/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "SupportedLanguages.h"
#import "PsiphonSettingsViewController.h"

#define EnglishLangIndex 0

#pragma mark - Lang data object

@implementation Language

+ (instancetype)createWithCode:(NSString *)code andLocalDescription:(NSString *)localDescription {
    Language *i = [[Language alloc] init];
    i->_code = code;
    i->_localDescription = localDescription;
    return i;
}

+ (Language *)currentLang {

    NSArray<Language *> *langs = [SupportedLanguages languageList];

    // This is bit of a hack for compatibility with PsiphonClientCommonLibrary
    NSString *_Nullable storedLangCode = [[NSUserDefaults standardUserDefaults]
      objectForKey:appLanguage];

    __block Language *_Nullable currentLang;

    [langs enumerateObjectsUsingBlock:^(Language *lang, NSUInteger idx, BOOL *stop) {
        if ([storedLangCode isEqualToString:lang.code]) {
            currentLang = lang;
            *stop = TRUE;
        }
    }];

    // If previously selected lang is empty, or it is no longer supported, return English.
    if (!currentLang) {
        currentLang = langs[EnglishLangIndex];
    }

    return currentLang;
}

+ (void)setCurrentLang:(Language *)lang {
    // This is bit of a hack to make the language selection compatible with
    // PsiphonClientCommonLibrary.
    [[NSUserDefaults standardUserDefaults] setObject:lang.code forKey:appLanguage];
}

@end

#pragma mark -

@implementation SupportedLanguages

+ (NSArray<Language *> *)languageList {
    return @[

      // English language is assumed to always be index 0.
      // Check `EnglishLangIndex`.
      [Language createWithCode:@"en"
           andLocalDescription:@"English"],

      [Language createWithCode:@"fa"
           andLocalDescription:@"فارسی"],

      [Language createWithCode:@"ar"
           andLocalDescription:@"العربية"],

      [Language createWithCode:@"zh-Hans"
           andLocalDescription:@"简体中文"],

      [Language createWithCode:@"zh-Hant"
           andLocalDescription:@"繁体中文"],

      [Language createWithCode:@"am"
           andLocalDescription:@"ኣማርኛ"],

      [Language createWithCode:@"az"
           andLocalDescription:@"Azərbaycanca"],

      [Language createWithCode:@"be"
           andLocalDescription:@"Беларуская"],

      [Language createWithCode:@"bo"
           andLocalDescription:@"བོད་ཡིག"],

      [Language createWithCode:@"bn"
           andLocalDescription:@"বাংলা"],

      [Language createWithCode:@"de"
           andLocalDescription:@"Deutsch"],

      [Language createWithCode:@"el"
           andLocalDescription:@"Ελληνικά"],

      [Language createWithCode:@"es"
           andLocalDescription:@"Español"],

      [Language createWithCode:@"fi"
           andLocalDescription:@"Suomi"],

      [Language createWithCode:@"fr"
           andLocalDescription:@"Français"],

      [Language createWithCode:@"hi"
           andLocalDescription:@"हिन्दी"],

      [Language createWithCode:@"hr"
           andLocalDescription:@"Hrvatski"],

      [Language createWithCode:@"id"
           andLocalDescription:@"Bahasa Indonesia"],

      [Language createWithCode:@"kk"
           andLocalDescription:@"Қазақша"],

      [Language createWithCode:@"km"
           andLocalDescription:@"ភាសាខ្មែរ"],

      [Language createWithCode:@"ko"
           andLocalDescription:@"한국어"],

      [Language createWithCode:@"ky"
           andLocalDescription:@"Кыргызча"],

      [Language createWithCode:@"my"
           andLocalDescription:@"မြန်မာစာ"],

      [Language createWithCode:@"nb"
           andLocalDescription:@"Norsk bokmål"],

      [Language createWithCode:@"nl"
           andLocalDescription:@"Nederlands"],

      [Language createWithCode:@"pt-BR"
           andLocalDescription:@"Português (Brasil)"],

      [Language createWithCode:@"pt-PT"
           andLocalDescription:@"Português (Portugal)"],

      [Language createWithCode:@"ru"
           andLocalDescription:@"Русский"],

      [Language createWithCode:@"tg"
           andLocalDescription:@"тоҷики"],

      [Language createWithCode:@"th"
           andLocalDescription:@"ภาษาไทย"],

      [Language createWithCode:@"tk"
           andLocalDescription:@"Türkmençe"],

      [Language createWithCode:@"tr"
           andLocalDescription:@"Türkçe"],

      [Language createWithCode:@"uk"
           andLocalDescription:@"Українська"],

      [Language createWithCode:@"uz"
           andLocalDescription:@"O&apos;zbekcha"],

      [Language createWithCode:@"vi"
           andLocalDescription:@"Tiếng Việt"],
    ];
}

@end
