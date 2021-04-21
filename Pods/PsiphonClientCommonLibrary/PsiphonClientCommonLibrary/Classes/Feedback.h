/*
 * Copyright (c) 2017, Psiphon Inc.
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
#import "PsiphonData.h"

NS_ASSUME_NONNULL_BEGIN

@interface Feedback : NSObject

/// Generates a random feedback ID.
/// @return 8 random bytes encoded as a 16 character hex string.
+ (NSString*_Nullable)generateFeedbackId;

/// Construct feedback JSON which conforms to the structure expected by the feedback template for iOS:
/// https://bitbucket.org/psiphon/psiphon-circumvention-system/src/default/EmailResponder/FeedbackDecryptor/templates/?at=default
/// This matches the feedback JSON scheme used by the Android client:
/// https://bitbucket.org/psiphon/psiphon-circumvention-system/src/default/Android/app/src/main/java/com/psiphon3/psiphonlibrary/Diagnostics.java
/// @param thumbIndex Index of the survey response.
/// @param buildInfo Client build information. Omitted from result if sendDiagnosticInfo is false.
/// @param comments User comments.
/// @param email User email.
/// @param sendDiagnosticInfo If true, the user opted in to sending diagnostic information and it will be included in the returned
/// JSON. Otherwise, diagnostic information will be omitted.
/// @param feedbackId Random 16 character hex string generated with `Feedback.generateFeedbackId`.
/// @param psiphonConfig A feedback compatible config. Config must be provided by Psiphon Inc.
/// @param clientPlatform Client platform.
/// @param connectionType Network type name (e.g. "WIFI"). Omitted from result if sendDiagnosticInfo is false.
/// @param isJailbroken True if the device is jailbroken, otherwise false. Omitted from result if sendDiagnosticInfo is false.
/// @param diagnosticEntries Diagnostic entries. Omitted from result if sendDiagnosticInfo is false.
/// @param statusEntries Status entries. Omitted from result if sendDiagnosticInfo is false.
/// @param outError If non-nil on return, then constructing the feedback JSON failed with the provided error.
/// @return Returns constructed feedback JSON serialized as a UTF-8 encoded string. Returns nil when `outError` is non-nil.
+ (NSString*_Nullable)generateFeedbackJSON:(NSInteger)thumbIndex
                                 buildInfo:(NSString*_Nullable)buildInfo
                                  comments:(NSString*_Nullable)comments
                                     email:(NSString*_Nullable)email
                        sendDiagnosticInfo:(BOOL)sendDiagnosticInfo
                                feedbackId:(NSString*)feedbackId
                             psiphonConfig:(NSDictionary*)psiphonConfig
                            clientPlatform:(NSString*_Nullable)clientPlatform
                            connectionType:(NSString*_Nullable)connectionType
                              isJailbroken:(BOOL)isJailbroken
                         diagnosticEntries:(NSArray<DiagnosticEntry *>*_Nullable)diagnosticEntries
                             statusEntries:(NSArray<StatusEntry *>*_Nullable)statusEntries
                                     error:(NSError*_Nullable*)outError;
@end

NS_ASSUME_NONNULL_END
