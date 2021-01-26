/*
 * Copyright (c) 2021, Psiphon Inc.
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
#import "Notifier.h"

NS_ASSUME_NONNULL_BEGIN

// HostAppProtocol defines a communications protocol between the networke extension
// and the host app based on Darwin notification message.
//
// - Note: This object does some book-keeping and only once instance should be created.
//
// TODO: Eventually all communications with the host app should be brought under a single umbrella here.
@interface HostAppProtocol : NSObject <NotifierObserver>

/// Liveness check for the host app process. If no reponse is provided by the host app,
/// `completionHandler` will be called with FALSE value.
- (void)isHostAppProcessRunning:(void (^)(BOOL isProcessRunning))completionHandler;

@end

NS_ASSUME_NONNULL_END
