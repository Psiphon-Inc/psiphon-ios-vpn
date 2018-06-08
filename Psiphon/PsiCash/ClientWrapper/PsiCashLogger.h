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

@interface PsiCashLogger : NSObject

- (id)initWithClient:(PsiCash*)client;

- (void)logEvent:(NSString*)event includingDiagnosticInfo:(BOOL)diagnosticInfo;

- (void)logEvent:(NSString*)event withInfo:(NSString*_Nullable)info includingDiagnosticInfo:(BOOL)diagnosticInfo;

- (void)logEvent:(NSString*)event withInfoDictionary:(NSDictionary*_Nullable)infoDictionary includingDiagnosticInfo:(BOOL)diagnosticInfo;

- (void)logErrorEvent:(NSString*)event withError:(NSError*_Nullable)error includingDiagnosticInfo:(BOOL)diagnosticInfo;

- (void)logErrorEvent:(NSString*)event withInfo:(NSString*_Nullable)info includingDiagnosticInfo:(BOOL)diagnosticInfo;

- (NSString*_Nullable)logForFeedback;

@end

NS_ASSUME_NONNULL_END
