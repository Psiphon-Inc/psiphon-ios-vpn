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

#pragma mark - App Info

/**
 * App string version from last lunch.
 * @return String version or nil if it doesn't exist.
 */
- (NSString *_Nullable)storedAppVersion;

/**
 * Stores current app version.
 * @param appVersion App version string should not be nil.
 */
- (void)storeCurrentAppVersion:(NSString *)appVersion;

#pragma mark - Onboarding

/**
 * Returns TRUE if user has finished onboarding, FALSE otherwise.
 */
- (BOOL)hasFinishedOnboarding;

/**
 * Sets internal flag that the user has finished onboarding. `- hasFinishedOnboarding` will return TRUE from now on.
 */
- (void)setHasFinishedOnboarding;

#pragma mark - Privacy Policy

/**
 * Returns RFC3339 formatted time of last update to Psiphon's Privacy Policy for iOS.
 */
- (NSString *)privacyPolicyLastUpdateTime;

/**
 * Returns RFC3339 formatted time of the privacy policy that was last accepted by the user.
 */
- (NSString *_Nullable)lastAcceptedPrivacyPolicy;

/**
 * Returns TRUE if the user has accepted the latest privacy policy, FALSE otherwise.
 */
- (BOOL)hasAcceptedLatestPrivacyPolicy;

/**
 * Stores privacyPolicyTimestamp as the privacy policy that was accepted.
 *
 * @note This is not the time that the user accepted the privacy policy, but rather,
 * the time that the privacy policy was updated.
 *
 * @param privacyPolicyTimestamp
 */
- (void)setAcceptedPrivacyPolicy:(NSString *)privacyPolicyTimestamp;

/**
 *
 * Stores `-privacyPolicyLastUpdateTime` as the privacy policy that was accepted.
 *
 * @note This is not the time that the user accepted the privacy policy, but rather,
 * the time that the privacy policy was updated.
 */
- (void)setAcceptedLatestPrivacyPolicy;

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
