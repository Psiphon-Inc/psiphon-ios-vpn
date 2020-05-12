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

#import <Foundation/Foundation.h>
#import "RunningBins.h"
#import "RunningStat.h"

NS_ASSUME_NONNULL_BEGIN

/// A representation of jetsam statistics across different app versions.
@interface JetsamMetrics : NSObject <NSCopying, NSCoding, NSSecureCoding>

@property (readonly, nonatomic, strong) NSDictionary <NSString *, RunningStat *> *perVersionMetrics;

/// Track the number of jetsams which fall within specific running time ranges.
/// @param binRanges Ranges to track.
- (instancetype)initWithBinRanges:(NSArray<BinRange*>*)binRanges;

/// Updates the jetsam statistics for the corresponding app version with the given running time.
/// @param appVersion Application version corresponding to jetsam event.
/// @param runningTime Amount of time the application ran before the jetsam occured.
- (void)addJetsamForAppVersion:(NSString*)appVersion
                   runningTime:(NSTimeInterval)runningTime;

- (BOOL)isEqualToJetsamMetrics:(JetsamMetrics*)jetsamMetrics;

@end

NS_ASSUME_NONNULL_END
