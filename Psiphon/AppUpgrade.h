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

@interface AppUpgrade : NSObject

/**
 * Handles app upgrade.
 * If this is an app upgrade, blocks until necessary app upgrade steps are done.
 *
 * This should be called in AppDelegate `-application:willFinishLaunchingWithOptions:` as the first
 * operation performed by the app, since the upgrade procedure is allowed to change any of the data
 * stored in the app.
 *
 * @return TRUE if this is the first run of current app version, FALSE otherwise.
 */
+ (BOOL)firstRunOfAppVersion;

@end

NS_ASSUME_NONNULL_END
