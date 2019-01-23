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

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

@interface Language : NSObject

@property (nonatomic, readonly) NSString *code;
@property (nonatomic, readonly) NSString *localDescription;

+ (instancetype)createWithCode:(NSString *)code andLocalDescription:(NSString *)localDescription;

/**
 * Returns currently selected language.
 * It defaults to English if no language was previously selected,
 * or if the previous language is no longer supported.
 */
+ (Language *)currentLang;

/**
 * Stores currently selected language.
 */
+ (void)setCurrentLang:(Language *)lang;

@end

@interface SupportedLanguages : NSObject

/**
 * Returns list of supported languages.
 */
+ (NSArray<Language *> *)languageList;

@end

NS_ASSUME_NONNULL_END
