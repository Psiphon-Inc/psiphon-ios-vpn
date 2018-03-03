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
#import <ReactiveObjC/RACDisposable.h>
#import "Subscription.h"
#import "NSDate+Comparator.h"
#import "NSError+Convenience.h"
#import "RACTuple.h"
#import "PsiFeedbackLogger.h"
#import "Logging.h"
#import "Asserts.h"

NSErrorDomain _Nonnull const ReceiptValidationErrorDomain = @"PsiphonReceiptValidationErrorDomain";

@implementation SubscriptionVerifierService {
    NSURLSession *urlSession;
}

+ (RACSignal<NSDictionary *> *)updateSubscriptionAuthorizationTokenFromRemote {
    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        SubscriptionVerifierService *service = [[SubscriptionVerifierService alloc] init];

        [service startWithCompletionHandler:^(NSDictionary *remoteAuthDict, NSNumber *submittedReceiptFileSize, NSError *error) {

            if (error) {
                [subscriber sendError:error];
            } else {
                [subscriber sendNext:[RACTwoTuple pack:remoteAuthDict :submittedReceiptFileSize]];
                [subscriber sendCompleted];
            }
        }];

        return [RACDisposable disposableWithBlock:^{
            @autoreleasepool {
                [service cancel];
            }
        }];

    }];
}

/**
 * Starts asynchronous task that upload current App Store receipt file to the subscription verifier server,
 * and calls receiptUploadCompletionHandler with the response from the server.
 * @param receiptUploadCompletionHandler Completion handler called with the result of the network request.
 */
- (void)startWithCompletionHandler:(SubscriptionVerifierCompletionHandler _Nonnull)receiptUploadCompletionHandler {
    NSMutableURLRequest *request;

    // Open a connection for the URL, configured to POST the file.

    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kRemoteVerificationURL]];

    NSNumber *appReceiptFileSize;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize forKey:NSURLFileSizeKey error:nil];

    [request setHTTPBodyStream:[NSInputStream inputStreamWithURL:NSBundle.mainBundle.appStoreReceiptURL]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

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
                    receiptUploadCompletionHandler(nil, appReceiptFileSize, err);
                    return;
                }

                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
                if (httpResponse.statusCode != 200) {
                    NSString *description = [NSString stringWithFormat:@"HTTP code: %ld", (long) httpResponse.statusCode];
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: description};
                    NSError *err = [[NSError alloc] initWithDomain:ReceiptValidationErrorDomain code:PsiphonReceiptValidationErrorHTTPFailed userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, appReceiptFileSize, err);
                    return;
                }

                if (data.length == 0) {
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: @"Empty server response"};
                    NSError *err = [[NSError alloc] initWithDomain:ReceiptValidationErrorDomain code:PsiphonReceiptValidationErrorInvalidReceipt userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, appReceiptFileSize, err);
                    return;
                }

                NSError *jsonError;
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];

                if (jsonError) {
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: @"JSON parse failure", NSUnderlyingErrorKey: error};
                    NSError *err = [[NSError alloc] initWithDomain:ReceiptValidationErrorDomain code:PsiphonReceiptValidationErrorJSONParseFailed userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, appReceiptFileSize, err);
                    return;
                }

                receiptUploadCompletionHandler(dict, appReceiptFileSize, nil);
            }
        });
    }];

    [postDataTask resume];
}

- (void)cancel {
    [urlSession invalidateAndCancel];
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

+ (RACSignal<NSNumber *> *_Nonnull)localSubscriptionCheck {
    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {
        Subscription *subscription = [Subscription fromPersistedDefaults];
        if ([subscription shouldUpdateSubscriptionToken]) {
            // subscription server needs to be contacted.
            [subscriber sendNext:@(SubscriptionCheckShouldUpdateToken)];
            [subscriber sendCompleted];
        } else {
            // subscription server doesn't need to be contacted.
            // Checks if subscription is active compared to device's clock.
            if ([subscription hasActiveSubscriptionTokenForDate:[NSDate date]]) {
                [subscriber sendNext:@(SubscriptionCheckHasActiveToken)];
                [subscriber sendCompleted];
            } else {
                // Send error, subscription has expired.
                [subscriber sendNext:@(SubscriptionCheckTokenExpired)];
                [subscriber sendCompleted];
            }
        }

        return nil;
    }];
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

- (BOOL)hasActiveSubscriptionForNow {
    return [self hasActiveSubscriptionTokenForDate:[NSDate date]];
}

- (BOOL)hasActiveSubscriptionTokenForDate:(NSDate *)date {
    if ([self isEmpty]) {
        return FALSE;
    }
    if (!self.authorizationToken) {
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
        LOG_DEBUG(@"receipt does not exist");
        return NO;
    }

    // There's receipt but no subscription persisted - YES
    if([self isEmpty]) {
        LOG_DEBUG(@"receipt exist by no subscription persisted");
        return YES;
    }

    // Receipt file size has changed since last check - YES
    NSNumber *currentReceiptFileSize;
    [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&currentReceiptFileSize forKey:NSURLFileSizeKey error:nil];
    if ([currentReceiptFileSize unsignedIntValue] != [self.appReceiptFileSize unsignedIntValue]) {
        LOG_DEBUG(@"receipt file size changed (%@) since last check (%@)", currentReceiptFileSize, self.appReceiptFileSize);
        return YES;
    }

    // If user has an active authorization for date - NO
    if ([self hasActiveSubscriptionTokenForDate:[NSDate date]]) {
        LOG_DEBUG(@"device has active authorization for date");
        return NO;
    }

    // If expired and pending renewal info is missing - YES
    if(!self.pendingRenewalInfo) {
        LOG_DEBUG(@"pending renewal info is missing");
        return YES;
    }

    // If expired but user's last known intention was to auto-renew - YES
    if([self.pendingRenewalInfo count] == 1
      && [self.pendingRenewalInfo[0] isKindOfClass:[NSDictionary class]]) {

        NSString *autoRenewStatus = [self.pendingRenewalInfo[0] objectForKey:kRemoteSubscriptionVerifierPendingRenewalInfoAutoRenewStatus];
        if (autoRenewStatus && [autoRenewStatus isEqualToString:@"1"]) {
            LOG_DEBUG(@"subscription expired but user's last known intention is to auto-renew");
            return YES;
        }
    }

    LOG_DEBUG(@"authorization token update not needed");
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

#pragma mark - Subscription Result Model

NSErrorDomain _Nonnull const SubscriptionResultErrorDomain = @"SubscriptionResultErrorDomain";

@interface SubscriptionResultModel ()

@property (nonatomic, readwrite, assign) BOOL inProgress;

/** Error with domain SubscriptionResultErrorDomain */
@property (nonatomic, readwrite, nullable) NSError *error;

@property (nonatomic, readwrite, nullable) NSDictionary *remoteAuthDict;

@property (nonatomic, readwrite, nullable) NSNumber *submittedReceiptFileSize;

@end

@implementation SubscriptionResultModel

+ (SubscriptionResultModel *_Nonnull)inProgress {
    SubscriptionResultModel *instance = [[SubscriptionResultModel alloc] init];
    instance.inProgress = TRUE;
    instance.error = nil;
    instance.remoteAuthDict = nil;
    instance.submittedReceiptFileSize = nil;
    return instance;
}

+ (SubscriptionResultModel *)failed:(SubscriptionResultErrorCode)errorCode {
    SubscriptionResultModel *instance = [[SubscriptionResultModel alloc] init];
    instance.inProgress = FALSE;
    instance.error = [NSError errorWithDomain:SubscriptionResultErrorDomain code:errorCode];
    instance.remoteAuthDict = nil;
    instance.submittedReceiptFileSize = nil;
    return instance;
}

+ (SubscriptionResultModel *)success:(NSDictionary *_Nullable)remoteAuthDict receiptFilSize:(NSNumber *_Nullable)receiptFileSize {
    SubscriptionResultModel *instance = [[SubscriptionResultModel alloc] init];
    instance.inProgress = FALSE;
    instance.error = nil;
    instance.remoteAuthDict = remoteAuthDict;
    instance.submittedReceiptFileSize = receiptFileSize;
    return instance;
}

@end

#pragma mark - Subscription state

typedef NS_ENUM(NSInteger, SubscriptionStateEnum) {
    SubscriptionStateNotSubscribed = 1,
    SubscriptionStateInProgress = 2,
    SubscriptionStateSubscribed = 3,
};

@implementation SubscriptionState {
    NSObject *_lock;
    SubscriptionStateEnum _state;
}

+ (SubscriptionState *_Nonnull)initialStateFromSubscription:(Subscription *)subscription {
    SubscriptionState *instance = [[SubscriptionState alloc] init];
    instance.state = SubscriptionStateNotSubscribed;

    if ([subscription hasActiveSubscriptionTokenForDate:[NSDate date]]) {
        instance.state = SubscriptionStateSubscribed;
    } else if ([subscription shouldUpdateSubscriptionToken]) {
        instance.state = SubscriptionStateInProgress;
    }

    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSObject alloc] init];
    }
    return self;
}

- (void)setState:(SubscriptionStateEnum)newState {
    @synchronized (_lock) {
        _state = newState;
    }
}

- (SubscriptionStateEnum)state {
    @synchronized (_lock) {
        PSIAssert(_state != 0);
        return _state;
    }
}

- (BOOL)isSubscribedOrInProgress {
    return self.state != SubscriptionStateNotSubscribed;
}

- (BOOL)isInProgress {
   return self.state == SubscriptionStateInProgress;
}

- (void)setStateSubscribed {
    self.state = SubscriptionStateSubscribed;
}

- (void)setStateInProgress {
    self.state = SubscriptionStateInProgress;
}

- (void)setStateNotSubscribed {
    self.state = SubscriptionStateNotSubscribed;
}

- (NSString *_Nonnull)textDescription {
    switch (self.state) {
        case SubscriptionStateNotSubscribed: return @"subscription state not subscribed";
        case SubscriptionStateInProgress: return @"subscription state in progress";
        case SubscriptionStateSubscribed: return @"subscription state subscribed";
    }
    return @"";
}

@end
