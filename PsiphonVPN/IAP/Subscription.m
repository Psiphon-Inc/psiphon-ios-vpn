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
#import "Subscription.h"
#import "SubscriptionReceiptInputStream.h"
#import "Logging.h"
#import "NSDate+Comparator.h"

NSString *_Nonnull const ReceiptValidationErrorDomain = @"PsiphonReceiptValidationErrorDomain";

@implementation SubscriptionVerifierTask {
    NSURLSession *urlSession;
}

- (void)startWithCompletionHandler:(SubscriptionVerifierCompletionHandler _Nonnull)receiptUploadCompletionHandler {
    NSMutableURLRequest *request;

    // Open a connection for the URL, configured to POST the file.

    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kRemoteVerificationURL]];
    assert(request != nil);

    [request setHTTPBodyStream:[[SubscriptionReceiptInputStream alloc] initWithURL:[NSBundle mainBundle].appStoreReceiptURL]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = kReceiptRequestTimeOutSeconds;

    urlSession = [NSURLSession sessionWithConfiguration:sessionConfig];

    NSURLSessionDataTask *postDataTask = [urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        dispatch_async(dispatch_get_main_queue(), ^{

            // Session is no longer needed, invalidates and cancels outstanding tasks.
            [urlSession invalidateAndCancel];

            if (receiptUploadCompletionHandler) {
                if (error) {
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: @"NSURLSession error", NSUnderlyingErrorKey: error};
                    NSError *err = [[NSError alloc] initWithDomain:ReceiptValidationErrorDomain code:PsiphonReceiptValidationErrorNSURLSessionFailed userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, err);
                    return;
                }

                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
                if (httpResponse.statusCode != 200) {
                    NSString *description = [NSString stringWithFormat:@"HTTP code: %ld", (long) httpResponse.statusCode];
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: description};
                    NSError *err = [[NSError alloc] initWithDomain:ReceiptValidationErrorDomain code:PsiphonReceiptValidationErrorHTTPFailed userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, err);
                    return;
                }

                if (data.length == 0) {
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: @"Empty server response"};
                    NSError *err = [[NSError alloc] initWithDomain:ReceiptValidationErrorDomain code:PsiphonReceiptValidationErrorInvalidReceipt userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, err);
                    return;
                }

                NSError *jsonError;
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];

                if (jsonError) {
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: @"JSON parse failure", NSUnderlyingErrorKey: error};
                    NSError *err = [[NSError alloc] initWithDomain:ReceiptValidationErrorDomain code:PsiphonReceiptValidationErrorJSONParseFailed userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, err);
                    return;
                }

                receiptUploadCompletionHandler(dict, nil);
            }
        });
    }];

    [postDataTask resume];
}

@end

// Subscription dictionary keys
#define kSubscriptionDictionary         @"kSubscriptionDictionary"
#define kAppReceiptFileSize             @"kAppReceiptFileSize"
#define kPendingRenewalInfo             @"kPendingRenewalInfo"
#define kSubscriptionAuthorizationToken @"kSubscriptionAuthorizationToken"

@implementation Subscription {
    NSMutableDictionary *dictionaryRepresentation;
}

+ (Subscription *_Nonnull)fromPersistedDefaults {
    Subscription *instance = [[Subscription alloc] init];
    NSDictionary *persistedDic = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSubscriptionDictionary];
    instance->dictionaryRepresentation = [[NSMutableDictionary alloc] initWithDictionary:persistedDic];
    return instance;
}

- (BOOL)isEmpty {
    return (self->dictionaryRepresentation == nil) || ([self->dictionaryRepresentation count] == 0);
}

- (BOOL)persistChanges {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:self->dictionaryRepresentation forKey:kSubscriptionDictionary];
    return [userDefaults synchronize];
}

- (NSNumber *_Nullable)appReceiptFileSize {
    return self->dictionaryRepresentation[kAppReceiptFileSize];
}

- (void)setAppReceiptFileSize:(NSNumber *_Nullable)fileSize {
    self->dictionaryRepresentation[kAppReceiptFileSize] = fileSize;
}

- (NSArray *_Nullable)pendingRenewalInfo {
    return self->dictionaryRepresentation[kPendingRenewalInfo];
}

- (void)setPendingRenewalInfo:(NSArray *)pendingRenewalInfo {
    self->dictionaryRepresentation[kPendingRenewalInfo] = pendingRenewalInfo;
}

- (AuthorizationToken *)authorizationToken {
    return [[AuthorizationToken alloc] initWithEncodedToken:self->dictionaryRepresentation[kSubscriptionAuthorizationToken]];
}

- (void)setAuthorizationToken:(AuthorizationToken *)authorizationToken {
    self->dictionaryRepresentation[kSubscriptionAuthorizationToken] = authorizationToken.base64Representation;
}

- (BOOL)hasActiveSubscriptionTokenForDate:(NSDate *)date {
    if ([self isEmpty]) {
        return FALSE;
    }
    return [self.authorizationToken.expires afterOrEqualTo:date];
}

- (BOOL)shouldUpdateSubscriptionToken {
    // If no receipt - NO
    NSURL *URL = [NSBundle mainBundle].appStoreReceiptURL;
    NSString *path = URL.path;
    const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil];
    if (!exists) {
        LOG_DEBUG_NOTICE(@"receipt does not exist");
        return NO;
    }

    // There's receipt but no subscription persisted - YES
    if([self isEmpty]) {
        LOG_DEBUG_NOTICE(@"receipt exist by no subscription persisted");
        return YES;
    }

    // Receipt file size has changed since last check - YES
    NSNumber *appReceiptFileSize = nil;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:nil];
    if ([appReceiptFileSize unsignedIntValue] != [self.appReceiptFileSize unsignedIntValue]) {
        LOG_DEBUG_NOTICE(@"receipt file size changed (%@) since last check (%@)", appReceiptFileSize, self.appReceiptFileSize);
        return YES;
    }

    // If user has an active authorization for date - NO
    if ([self hasActiveSubscriptionTokenForDate:[NSDate date]]) {
        LOG_DEBUG_NOTICE(@"device has active authorization for date");
        return NO;
    }

    // If expired and pending renewal info is missing - YES
    if(!self.pendingRenewalInfo) {
        LOG_DEBUG_NOTICE(@"pending renewal info is missing");
        return YES;
    }

    // If expired but user's last known intention was to auto-renew - YES
    if([self.pendingRenewalInfo count] == 1
      && [self.pendingRenewalInfo[0] isKindOfClass:[NSDictionary class]]) {

        NSString *autoRenewStatus = [self.pendingRenewalInfo[0] objectForKey:kRemoteSubscriptionVerifierPendingRenewalInfoAutoRenewStatus];
        if (autoRenewStatus && [autoRenewStatus isEqualToString:@"1"]) {
            LOG_DEBUG_NOTICE(@"subscription expired but user's last known intention is to auto-renew");
            return YES;
        }
    }

    LOG_DEBUG_NOTICE(@"authorization token update not needed");
    return NO;
}

- (NSError *)updateSubscriptionWithRemoteAuthDict:(NSDictionary *)remoteAuthDict {

    if (!remoteAuthDict) {
        return nil;
    }

    // Gets app subscription receipt file size.
    NSError *err;
    NSNumber *appReceiptFileSize = nil;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:&err];
    if (err) {
        return err;
    }

    // Updates subscription dictionary.
    [self setAppReceiptFileSize:appReceiptFileSize];
    [self setPendingRenewalInfo:remoteAuthDict[kRemoteSubscriptionVerifierPendingRenewalInfo]];
    AuthorizationToken *token = [[AuthorizationToken alloc]
      initWithEncodedToken:remoteAuthDict[kRemoteSubscriptionVerifierSignedAuthorization]];
    [self setAuthorizationToken:token];

    return nil;
}

@end
