/*
 * Copyright (c) 2016, Psiphon Inc.
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

#define kRegionSelectionSpecifierKey	@"regionSelection"
#define kPsiphonAvailableRegionsNotification @"kPsiphonAvailableRegionsNotification"
#define kPsiphonSelectedNewRegionNotification @"kPsiphonSelectedNewRegionNotification"
#define kPsiphonRegionBestPerformance @""

@interface Region : NSObject
@property (readonly, strong, nonatomic) NSString *code;
@property (readonly, strong, nonatomic) NSString *flagResourceId;
@property (readonly, nonatomic) BOOL serverExists;
@end

@protocol RegionAdapterDelegate <NSObject>
- (void)selectedRegionDisappearedThenSwitchedToBestPerformance;
@end

@interface RegionAdapter : NSObject
@property (weak, nonatomic) id<RegionAdapterDelegate> delegate;
+ (instancetype)sharedInstance;
- (void)onAvailableEgressRegions:(NSArray*)availableEgressRegions;
- (void)setSelectedRegion:(NSString*)regionCode;
- (void)reloadTitlesForNewLocalization;
- (NSArray*)getRegions;
// Returns all possible region codes.
// e.g. @[@"AT", @"BE", ...]
- (NSArray*)getAllPossibleRegionCodes;
- (Region*)getSelectedRegion;
- (NSString*)getLocalizedRegionTitle:(NSString*)regionCode;
@end
