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

#import <PsiCashLib/PsiCash.h>
#import "PsiCashLogger.h"
#import "PsiFeedbackLogger.h"

NS_ASSUME_NONNULL_BEGIN

PsiFeedbackLogType const PsiCashLogType = @"PsiCash";

NSErrorDomain const PsiCashClientErrorDomain = @"PsiCashClientErrorDomain";

@implementation PsiCashLogger {
    PsiCash *psiCash;
}

- (id)initWithClient:(PsiCash*)client {
    self = [super init];
    if (self) {
        psiCash = client;
    }

    return self;
}

- (void)logEvent:(NSString*)event includingDiagnosticInfo:(BOOL)diagnosticInfo {
    [self logEvent:event withInfo:nil andError:nil includingDiagnosticInfo:diagnosticInfo isError:NO];
}

- (void)logEvent:(NSString*)event withInfo:(NSString*_Nullable)info includingDiagnosticInfo:(BOOL)diagnosticInfo {
    [self logEvent:event withInfo:info andError:nil includingDiagnosticInfo:diagnosticInfo isError:NO];
}

- (void)logEvent:(NSString*)event withInfoDictionary:(NSDictionary*_Nullable)infoDictionary includingDiagnosticInfo:(BOOL)diagnosticInfo {
    [self logEvent:event withInfo:infoDictionary andError:nil includingDiagnosticInfo:diagnosticInfo isError:NO];
}

- (void)logErrorEvent:(NSString*)event withError:(NSError*_Nullable)error includingDiagnosticInfo:(BOOL)diagnosticInfo {
    [self logEvent:event withInfo:nil andError:error includingDiagnosticInfo:diagnosticInfo isError:YES];
}

- (void)logErrorEvent:(NSString*)event withInfo:(NSString*_Nullable)info includingDiagnosticInfo:(BOOL)diagnosticInfo {
    [self logEvent:event withInfo:info andError:nil includingDiagnosticInfo:diagnosticInfo isError:YES];
}

- (void)logEvent:(NSString*)event withInfo:(NSObject*_Nullable)info andError:(NSError*_Nullable)error includingDiagnosticInfo:(BOOL)includeDiagnosticInfo isError:(BOOL)isError {
    NSMutableDictionary *log = [[NSMutableDictionary alloc] initWithDictionary:@{@"event": event}];

    if (info) {
        [log setObject:info forKey:@"info"];
    }

    if (includeDiagnosticInfo) {
        [log setObject:[psiCash getDiagnosticInfo] forKey:@"diagnosticInfo"];
    }

    if (error) {
        [log setObject:[PsiFeedbackLogger unpackError:error] forKey:@"NSError"];
    }

    if (![NSJSONSerialization isValidJSONObject:log]) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType format:@"invalid JSON object"];
        return;
    }

    if (isError || error) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType json:log];
    } else {
        [PsiFeedbackLogger infoWithType:PsiCashLogType json:log];
    }
}

- (NSString*_Nullable)logForFeedback {
    NSDictionary *log = @{
                          @"PsiCash": @{
                                  @"event": @"FeedbackUpload",
                                  @"diagnosticInfo": [psiCash getDiagnosticInfo]
                                  }
                          };

    if (![NSJSONSerialization isValidJSONObject:log]) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType format:@"invalid JSON object"];
        return nil;
    }

    NSError *writeError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:log options:0 error:&writeError];
    if (writeError) {
        [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"failed to serialize log for feedback" object:writeError];
        return nil;
    }

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    return [NSString stringWithFormat:@"%@: %@", @"ContainerInfo", jsonString];
}

@end

NS_ASSUME_NONNULL_END
