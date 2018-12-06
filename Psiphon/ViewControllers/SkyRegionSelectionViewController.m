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

#import "SkyRegionSelectionViewController.h"
#import "RegionAdapter.h"
#import "ImageUtils.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "Strings.h"


@implementation SkyRegionSelectionViewController {
    NSArray<Region *> *regions;
}

- (instancetype)initWithCurrentlySelectedRegionCode:(NSString *)currentRegionCode {
    self = [super init];
    if (self) {

        self.title = [Strings connectVia];

        regions = [[[RegionAdapter sharedInstance] getRegions]
      filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Region *evaluatedObject,
        NSDictionary<NSString *, id> *bindings) {
            return evaluatedObject.serverExists;
      }]];

        [regions enumerateObjectsUsingBlock:^(Region *r, NSUInteger idx, BOOL *stop) {
            if ([r.code isEqualToString:currentRegionCode]) {
                self.selectedIndex = idx;
                *stop = TRUE;
            }
        }];
    }
    return self;
}

- (NSUInteger)numberOfRows {
    return [regions count];
}

- (void)bindDataToCell:(UITableViewCell *)cell atRow:(NSUInteger)rowIndex {
    Region *r = regions[rowIndex];

    cell.textLabel.text = [[RegionAdapter sharedInstance]
      getLocalizedRegionTitle:r.code];

    UIImage *flag = [PsiphonClientCommonLibraryHelpers
      imageFromCommonLibraryNamed:r.flagResourceId];

    cell.imageView.image = [ImageUtils highlightImageWithRoundedCorners:flag];
}

- (void)onSelectedRow:(NSUInteger)rowIndex {
    if (self.selectionHandler) {
        self.selectionHandler(rowIndex, regions[rowIndex], self);
    }
}

@end
