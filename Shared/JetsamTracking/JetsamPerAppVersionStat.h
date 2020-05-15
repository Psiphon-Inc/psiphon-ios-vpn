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
#import "RunningStat.h"

NS_ASSUME_NONNULL_BEGIN

/// Jetsam stat calculated per app version.
@interface JetsamPerAppVersionStat : NSObject <NSCopying, NSCoding, NSSecureCoding>

/// Stat for the amount of time the extension ran before each jetsam.
@property (nonatomic, strong) RunningStat *runningTime;

/// Stat for the amount of time between jetsam events.
@property (nonatomic, strong) RunningStat *timeBetweenJetsams;

- (BOOL)isEqualToJetsamPerAppVersionStat:(JetsamPerAppVersionStat*)stat;

@end

NS_ASSUME_NONNULL_END
