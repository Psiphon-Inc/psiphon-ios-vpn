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

#import "RegionAdapter.h"
#import "PsiphonClientCommonLibraryHelpers.h"


@implementation Region

@synthesize code = _code;
@synthesize flagResourceId = _flagResourceId;
@synthesize serverExists = _serverExists;

- (id) init {
    self = [super init];
    return self;
}

- (id) initWithParams:(NSString*)regionCode andResourceId:(NSString*)pathToFlagResource exists:(BOOL) exists {
    self = [super init];
    if (self) {
        _code = regionCode;
        _flagResourceId = pathToFlagResource;
        _serverExists = exists;
    }
    return self;
}

- (void)setRegionExists:(BOOL)exists {
    _serverExists = exists;
}

@end

@implementation RegionAdapter {
    NSMutableArray *flags;
    NSMutableArray *regions;
    NSDictionary *regionTitles;
    NSString *selectedRegion;
}

- (id)init {
    self = [super init];
    selectedRegion = [[NSUserDefaults standardUserDefaults] stringForKey:kRegionSelectionSpecifierKey];

    if (selectedRegion == nil) {
        selectedRegion = kPsiphonRegionBestPerformance;
    }

    // Haskell to generate the following list. Update the comment and generate a new list when
    // adding a new server region.
    // $ ghci
    // > let f x = case x of; [] -> return (); (x:xs) -> (putStrLn $ "[[Region alloc] initWithParams:@\"" <> map Data.Char.toUpper x <> "\" andResourceId:@\"flag-" <> map Data.Char.toLower x <> "\" exists:NO],") >> f xs;
    // > f (Data.List.sort ["AR","AT","AU","BE","BG","BR","CA","CH","CL","CZ","DE","DK","EE","ES","FI","FR","GB","HU","IE","IN","IS","IT","JP","KE","KR","LV","MX","NL","NO","PL","RO","RS","SE","SG","SK","TW","US","ZA"])
    regions = [[NSMutableArray alloc] initWithArray:
               @[[[Region alloc] initWithParams:kPsiphonRegionBestPerformance andResourceId:@"flag-best-performance" exists:YES],
                 [[Region alloc] initWithParams:@"AE" andResourceId:@"flag-ae" exists:NO],
                 [[Region alloc] initWithParams:@"AR" andResourceId:@"flag-ar" exists:NO],
                 [[Region alloc] initWithParams:@"AT" andResourceId:@"flag-at" exists:NO],
                 [[Region alloc] initWithParams:@"AU" andResourceId:@"flag-au" exists:NO],
                 [[Region alloc] initWithParams:@"BE" andResourceId:@"flag-be" exists:NO],
                 [[Region alloc] initWithParams:@"BG" andResourceId:@"flag-bg" exists:NO],
                 [[Region alloc] initWithParams:@"BR" andResourceId:@"flag-br" exists:NO],
                 [[Region alloc] initWithParams:@"CA" andResourceId:@"flag-ca" exists:NO],
                 [[Region alloc] initWithParams:@"CH" andResourceId:@"flag-ch" exists:NO],
                 [[Region alloc] initWithParams:@"CL" andResourceId:@"flag-cl" exists:NO],
                 [[Region alloc] initWithParams:@"CZ" andResourceId:@"flag-cz" exists:NO],
                 [[Region alloc] initWithParams:@"DE" andResourceId:@"flag-de" exists:NO],
                 [[Region alloc] initWithParams:@"DK" andResourceId:@"flag-dk" exists:NO],
                 [[Region alloc] initWithParams:@"EE" andResourceId:@"flag-ee" exists:NO],
                 [[Region alloc] initWithParams:@"ES" andResourceId:@"flag-es" exists:NO],
                 [[Region alloc] initWithParams:@"FI" andResourceId:@"flag-fi" exists:NO],
                 [[Region alloc] initWithParams:@"FR" andResourceId:@"flag-fr" exists:NO],
                 [[Region alloc] initWithParams:@"GB" andResourceId:@"flag-gb" exists:NO],
                 [[Region alloc] initWithParams:@"GR" andResourceId:@"flag-gr" exists:NO],
                 [[Region alloc] initWithParams:@"HR" andResourceId:@"flag-hr" exists:NO],
                 [[Region alloc] initWithParams:@"HU" andResourceId:@"flag-hu" exists:NO],
                 [[Region alloc] initWithParams:@"ID" andResourceId:@"flag-id" exists:NO],
                 [[Region alloc] initWithParams:@"IE" andResourceId:@"flag-ie" exists:NO],
                 [[Region alloc] initWithParams:@"IN" andResourceId:@"flag-in" exists:NO],
                 [[Region alloc] initWithParams:@"IS" andResourceId:@"flag-is" exists:NO],
                 [[Region alloc] initWithParams:@"IT" andResourceId:@"flag-it" exists:NO],
                 [[Region alloc] initWithParams:@"JP" andResourceId:@"flag-jp" exists:NO],
                 [[Region alloc] initWithParams:@"KE" andResourceId:@"flag-ke" exists:NO],
                 [[Region alloc] initWithParams:@"KR" andResourceId:@"flag-kr" exists:NO],
                 [[Region alloc] initWithParams:@"LV" andResourceId:@"flag-lv" exists:NO],
                 [[Region alloc] initWithParams:@"MX" andResourceId:@"flag-mx" exists:NO],
                 [[Region alloc] initWithParams:@"NL" andResourceId:@"flag-nl" exists:NO],
                 [[Region alloc] initWithParams:@"NO" andResourceId:@"flag-no" exists:NO],
                 [[Region alloc] initWithParams:@"NZ" andResourceId:@"flag-nz" exists:NO],
                 [[Region alloc] initWithParams:@"PL" andResourceId:@"flag-pl" exists:NO],
                 [[Region alloc] initWithParams:@"PT" andResourceId:@"flag-pt" exists:NO],
                 [[Region alloc] initWithParams:@"RO" andResourceId:@"flag-ro" exists:NO],
                 [[Region alloc] initWithParams:@"RS" andResourceId:@"flag-rs" exists:NO],
                 [[Region alloc] initWithParams:@"SE" andResourceId:@"flag-se" exists:NO],
                 [[Region alloc] initWithParams:@"SG" andResourceId:@"flag-sg" exists:NO],
                 [[Region alloc] initWithParams:@"SK" andResourceId:@"flag-sk" exists:NO],
                 [[Region alloc] initWithParams:@"TW" andResourceId:@"flag-tw" exists:NO],
                 [[Region alloc] initWithParams:@"UA" andResourceId:@"flag-ua" exists:NO],
                 [[Region alloc] initWithParams:@"US" andResourceId:@"flag-us" exists:NO],
                 [[Region alloc] initWithParams:@"ZA" andResourceId:@"flag-za" exists:NO],
               ]];

    regionTitles = [RegionAdapter getLocalizedRegionTitles];

    return self;
}

+ (NSDictionary*)getLocalizedRegionTitles {
    // Haskell to generate the following list. Update the comment and generate a new list when
    // adding a new server region.
    // $ ghci
    // > let f x = case x of; [] -> return (); ((code,name):xs) -> (putStrLn $ "@\"" <> map Data.Char.toUpper code <> "\": NSLocalizedStringWithDefaultValue(@\"SERVER_REGION_" <> map Data.Char.toUpper code <> "\", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @\"" <> name <> "\", @\"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country.\"),") >> f xs;
    // > f (Data.List.sort [("AE","United Arab Emirates"),("AR","Argentina"),("AT","Austria"),("AU","Australia"),("BE","Belgium"),("BG","Bulgaria"),("BR","Brazil"),("CA","Canada"),("CH","Switzerland"),("CL","Chile"),("CZ","Czech Republic"),("DE","Germany"),("DK","Denmark"),("EE","Estonia"),("ES","Spain"),("FI","Finland"),("FR","France"),("GB","United Kingdom"),("GR","Greece"),("HR", "Croatia"),("HU","Hungary"),("ID", "Indonesia"),("IE","Ireland"),("IN","India"),("IS","Iceland"),("IT","Italy"),("JP","Japan"),("KE","Kenya"),("KR","Korea"),("LV","Latvia"),("MX","Mexico"),("NL","Netherlands"),("NO","Norway"),("NZ","New Zealand"),("PL","Poland"),("PT","Portugal"),("RO","Romania"),("RS","Serbia"),("SE","Sweden"),("SG","Singapore"),("SK","Slovakia"),("TW","Taiwan"),("UA", "Ukraine"),("US","United States"),("ZA","South Africa")])
    return @{
             kPsiphonRegionBestPerformance: NSLocalizedStringWithDefaultValue(@"SERVER_REGION_BEST_PERFORMANCE", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Best performance",@"The name of the pseudo-region a user can select if they want to use a Psiphon server with the best performance -- speed, latency, etc., rather than specify a particular region/country. This appears in a combo box and should be kept short."),
             @"AE": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_AE", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"United Arab Emirates", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"AR": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_AR", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Argentina", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"AT": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_AT", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Austria", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"AU": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_AU", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Australia", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"BE": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_BE", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Belgium", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"BG": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_BG", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Bulgaria", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"BR": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_BR", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Brazil", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"CA": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_CA", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Canada", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"CH": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_CH", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Switzerland", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"CL": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_CL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Chile", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"CZ": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_CZ", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Czech Republic", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"DE": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_DE", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Germany", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"DK": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_DK", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Denmark", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"EE": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_EE", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Estonia", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"ES": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_ES", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Spain", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"FI": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_FI", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Finland", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"FR": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_FR", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"France", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"GB": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_GB", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"United Kingdom", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"GR": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_GR", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Greece", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"HR": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_HR", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Croatia", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"HU": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_HU", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Hungary", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"ID": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_ID", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Indonesia", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"IE": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_IE", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Ireland", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"IN": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_IN", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"India", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"IS": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_IS", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Iceland", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"IT": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_IT", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Italy", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"JP": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_JP", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Japan", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"KE": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_KE", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Kenya", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"KR": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_KR", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Korea", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"LV": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_LV", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Latvia", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"MX": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_MX", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Mexico", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"NL": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_NL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Netherlands", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"NO": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_NO", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Norway", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"NZ": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_NZ", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"New Zealand", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"PL": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_PL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Poland", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"PT": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_PT", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Portugal", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"RO": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_RO", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Romania", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"RS": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_RS", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Serbia", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"SE": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_SE", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Sweden", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"SG": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_SG", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Singapore", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"SK": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_SK", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Slovakia", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"TW": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_TW", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Taiwan", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"UA": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_UA", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Ukraine", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"US": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_US", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"United States", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             @"ZA": NSLocalizedStringWithDefaultValue(@"SERVER_REGION_ZA", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"South Africa", @"Name of a country/region where Psiphon servers are located. The user can choose to only use servers in that country."),
             };
}

// See comment in header.
- (NSArray*)getAllPossibleRegionCodes {
    NSMutableArray *regionCodes = [[NSMutableArray alloc] initWithCapacity:regions.count];
    for (Region *region in regions) {
        [regionCodes addObject:region.code];
    }

    return regionCodes;
}

+ (instancetype)sharedInstance
{
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

// Localizes the region titles for display in the settings menu
// This should be called whenever the app language is changed
- (void)reloadTitlesForNewLocalization {
    regionTitles = [NSMutableDictionary dictionaryWithDictionary:[RegionAdapter getLocalizedRegionTitles]];
}

- (void)onAvailableEgressRegions:(NSArray*)availableEgressRegions {
    // If selected region is no longer available select best performance and restart
    if (![selectedRegion isEqualToString:kPsiphonRegionBestPerformance] && ![availableEgressRegions containsObject:selectedRegion]) {
        selectedRegion = kPsiphonRegionBestPerformance;
        id<RegionAdapterDelegate> strongDelegate = self.delegate;
        if ([strongDelegate respondsToSelector:@selector(selectedRegionDisappearedThenSwitchedToBestPerformance)]) {
            [strongDelegate selectedRegionDisappearedThenSwitchedToBestPerformance];
        }
    }

    // Should use a dictionary for performance if # of regions ever increases dramatically
    for (Region *region in regions) {
        [region setRegionExists:([region.code isEqualToString:kPsiphonRegionBestPerformance] || [availableEgressRegions containsObject:region.code])];
    }

    [self notifyAvailableRegionsChanged];
}

- (NSArray*)getRegions {
    return [regions copy];
}

- (Region*)getSelectedRegion {
    for (Region *region in regions) {
        if ([region.code isEqualToString:selectedRegion]) {
            return region;
        }
    }
    return nil;
}

- (void)setSelectedRegion:(NSString*)regionCode {
    selectedRegion = regionCode;
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setValue:selectedRegion forKey:kRegionSelectionSpecifierKey];
    [self notifySelectedNewRegion];
}

- (NSString*)getLocalizedRegionTitle:(NSString*)regionCode {
    NSString *localizedTitle = [regionTitles objectForKey:regionCode];
    if (localizedTitle.length == 0) {
        return @"";
    }
    return localizedTitle;
}

- (void)notifyAvailableRegionsChanged {
    [[NSNotificationCenter defaultCenter]
     postNotificationName:kPsiphonAvailableRegionsNotification
     object:self
     userInfo:nil];
}

-(void)notifySelectedNewRegion {
    [[NSNotificationCenter defaultCenter]
     postNotificationName:kPsiphonSelectedNewRegionNotification
     object:self
     userInfo:nil];
}

@end
