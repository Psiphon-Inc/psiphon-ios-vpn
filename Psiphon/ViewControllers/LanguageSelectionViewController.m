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

#import "LanguageSelectionViewController.h"
#import "SupportedLanguages.h"
#import "Strings.h"

@implementation LanguageSelectionViewController {
    NSArray<Language *> *langs;
}

- (instancetype)initWithSupportedLanguages {
    self = [super init];
    if (self) {
        self.title = [Strings selectLanguageTitle];
        langs = [SupportedLanguages languageList];
        Language *currentLang = [Language currentLang];

        // Find the index of currently selected language.
        [langs enumerateObjectsUsingBlock:^(Language *lang, NSUInteger idx, BOOL *stop) {
            if ([currentLang.code isEqualToString:lang.code]) {
                self.selectedIndex = idx;
                *stop = TRUE;
            }
        }];

    }
    return self;
}

- (NSUInteger)numberOfRows {
    return [langs count];
}

- (void)bindDataToCell:(UITableViewCell *)cell atRow:(NSUInteger)rowIndex {
    cell.textLabel.text = langs[rowIndex].localDescription;
}

- (void)onSelectedRow:(NSUInteger)rowIndex {
    // Stores the newly selected language and calls the selection handler.
    Language *selectedLang = langs[rowIndex];
    [Language setCurrentLang:selectedLang];

    if (self.selectionHandler) {
        self.selectionHandler(rowIndex, selectedLang, self);
    }
}

@end
