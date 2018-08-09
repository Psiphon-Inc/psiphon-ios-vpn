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

@interface MoPubConsent : NSObject

/**
 * Loads MoPub consent status if already given, or collects consent from the user if needed.
 * Once consent has been collected, or is already collected or is not needed, completion will be called with nil error.
 * If an error happens while collecting consent, completion is called with the underlying error passed in.
 */
+ (void)collectConsentWithCompletionHandler:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
