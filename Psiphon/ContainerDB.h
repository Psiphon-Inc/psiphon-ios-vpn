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

@interface ContainerDB : NSObject

#pragma mark - Privacy Policy

/**
 * Returns date of last update to Psiphon's Privacy Policy for iOS.
 */
- (NSDate *)privacyPolicyUpdateDate;

/**
 * Returns the date of the privacy policy that was last accepted by the user.
 */
- (NSDate *_Nullable)lastAcceptedPrivacyPolicy;

/**
 * Stores privacyPolicyDate as the date of the privacy policy that was accepted.
 * Note that this is not the date that the user accepted the privacy policy, but rather,
 * the date that the privacy policy was updated.
 */
- (void)setAcceptedPrivacyPolicy:(NSDate *)privacyPolicyDate;

/**
 * Sets set of egress regions in standard NSUserDefaults
 */
- (void)setEmbeddedEgressRegions:(NSArray<NSString *> *_Nullable)regions;

/**
 * Array of region codes.
 */
- (NSArray<NSString *> *_Nullable)embeddedEgressRegions;

@end

NS_ASSUME_NONNULL_END
