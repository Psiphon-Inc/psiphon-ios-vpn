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

NS_ASSUME_NONNULL_BEGIN

/// Persisted data used to track jetsam events in the extension.
@interface PersistentJetsamData : NSObject

/// Time when the extension was last started.
+ (NSDate*)extensionStartTime;
+ (void)setExtensionStartTimeToNow;

/// Time when the ticker last fired in the extension.
+ (NSDate*)tickerTime;
+ (void)setTickerTimeToNow;

@end

NS_ASSUME_NONNULL_END
