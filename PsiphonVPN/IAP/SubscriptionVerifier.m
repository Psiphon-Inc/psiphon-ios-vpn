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
#import "SubscriptionVerifier.h"
#import "SubscriptionReceiptInputStream.h"

@implementation SubscriptionVerifier {
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

    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = kReceiptRequestTimeOutSeconds;

    urlSession = [NSURLSession sessionWithConfiguration:sessionConfig];

    NSURLSessionDataTask *postDataTask = [urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        dispatch_async(dispatch_get_main_queue(), ^{

            [urlSession invalidateAndCancel];

            if (receiptUploadCompletionHandler) {
                if (error) {
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: @"NSURLSession error", NSUnderlyingErrorKey: error};
                    NSError *err = [[NSError alloc] initWithDomain:kReceiptValidationErrorDomain code:PsiphonReceiptValidationNSURLSessionError userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, err);
                    return;
                }

                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
                if (httpResponse.statusCode != 200) {
                    NSString *description = [NSString stringWithFormat:@"HTTP code: %ld", (long) httpResponse.statusCode];
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: description};
                    NSError *err = [[NSError alloc] initWithDomain:kReceiptValidationErrorDomain code:PsiphonReceiptValidationHTTPError userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, err);
                    return;
                }

                if (data.length == 0) {
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: @"Empty server response"};
                    NSError *err = [[NSError alloc] initWithDomain:kReceiptValidationErrorDomain code:PsiphonReceiptValidationInvalidReceiptError userInfo:errorDict];
                    receiptUploadCompletionHandler(nil, err);
                    return;
                }

                NSError *jsonError;
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];

                if (jsonError) {
                    NSDictionary *errorDict = @{NSLocalizedDescriptionKey: @"JSON parse failure", NSUnderlyingErrorKey: error};
                    NSError *err = [[NSError alloc] initWithDomain:kReceiptValidationErrorDomain code:PsiphonReceiptValidationJSONParseError userInfo:errorDict];
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
