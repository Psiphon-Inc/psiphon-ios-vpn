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
#import "MTBase64InputStream.h"

enum {
    // must be divisible by 4 for the Base64 streamer
    kPostBufferSize = 16384
};

@interface SubscriptionVerifier () <NSStreamDelegate>

@property (nonatomic, copy,   readwrite) NSData *           bodyPrefixData;
@property (nonatomic, strong, readwrite) NSInputStream *    base64encodedFileStream;
@property (nonatomic, copy,   readwrite) NSData *           bodySuffixData;
@property (nonatomic, strong, readwrite) NSOutputStream *   producerStream;
@property (nonatomic, strong, readwrite) NSInputStream *    consumerStream;
@property (nonatomic, assign, readwrite) const uint8_t *    buffer;
@property (nonatomic, assign, readwrite) uint8_t *          bufferOnHeap;
@property (nonatomic, assign, readwrite) size_t             bufferOffset;
@property (nonatomic, assign, readwrite) size_t             bufferLimit;
@property (nonatomic, strong, readwrite) NSThread *         streamThread;
@end


@implementation SubscriptionVerifier

- (void)startWithCompletionHandler:(SubscriptionVerifierCompletionHandler)receiptUploadCompletionHandler {
    NSURL *                 sendURL;
    NSMutableURLRequest *   request;
    NSString *              bodyPrefixStr;
    NSString *              bodySuffixStr;
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;

    assert(self.bodyPrefixData == nil);     // ditto
    assert(self.base64encodedFileStream == nil);         // ditto
    assert(self.bodySuffixData == nil);     // ditto
    assert(self.consumerStream == nil);     // ditto
    assert(self.producerStream == nil);     // ditto
    assert(self.buffer == NULL);            // ditto
    assert(self.bufferOnHeap == NULL);      // ditto

    bodyPrefixStr = @"{\"receipt-data\":\"";

    bodySuffixStr = @"\"}";

    self.bodyPrefixData = [bodyPrefixStr dataUsingEncoding:NSASCIIStringEncoding];
    assert(self.bodyPrefixData != nil);
    self.bodySuffixData = [bodySuffixStr dataUsingEncoding:NSASCIIStringEncoding];
    assert(self.bodySuffixData != nil);


    // Open a stream for the file we're going to send.  We open this stream
    // straight away because there's no need to delay.

    self.base64encodedFileStream = [[MTBase64InputStream alloc] initWithURL:[NSBundle mainBundle].appStoreReceiptURL];
    assert(self.base64encodedFileStream != nil);

    [self.base64encodedFileStream open];

    CFStreamCreateBoundPair(NULL, &readStream, &writeStream, kPostBufferSize);

    self.consumerStream = (__bridge_transfer NSInputStream *)readStream;
    self.producerStream = (__bridge_transfer NSOutputStream *)writeStream;


    self.producerStream.delegate = self;
    self.streamThread = [[NSThread alloc] initWithTarget:self selector:@selector(openProducerStream:) object:nil];

    [self.streamThread start];

    // Set up our state to send the body prefix first.

    self.buffer      = [self.bodyPrefixData bytes];
    self.bufferLimit = [self.bodyPrefixData length];

    // Open a connection for the URL, configured to POST the file.

    sendURL = [NSURL URLWithString:kRemoteVerificationURL];

    request = [NSMutableURLRequest requestWithURL:sendURL];
    assert(request != nil);

    [request setHTTPMethod:@"POST"];
    [request setHTTPBodyStream:self.consumerStream];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = receiptRequestTimeOutSeconds;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

    NSURLSessionDataTask *postDataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (receiptUploadCompletionHandler) {
            if (error) {
                NSDictionary *errorDict = @{ NSLocalizedDescriptionKey : @"NSURLSession error", NSUnderlyingErrorKey: error};
                NSError *err = [[NSError alloc] initWithDomain:kReceiptValidationErrorDomain code:PsiphonReceiptValidationNSURLSessionError userInfo:errorDict];
                receiptUploadCompletionHandler(nil, err);
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
            if(httpResponse.statusCode != 200) {
                NSString *description = [NSString stringWithFormat:@"HTTP code: %ld", (long)httpResponse.statusCode];
                NSDictionary *errorDict = @{ NSLocalizedDescriptionKey : description};
                NSError *err = [[NSError alloc] initWithDomain:kReceiptValidationErrorDomain code:PsiphonReceiptValidationHTTPError userInfo:errorDict];
                receiptUploadCompletionHandler(nil, err);
                return;
            }

            if(data.length == 0) {
                NSDictionary *errorDict = @{ NSLocalizedDescriptionKey : @"Empty server response"};
                NSError *err = [[NSError alloc] initWithDomain:kReceiptValidationErrorDomain code:PsiphonReceiptValidationInvalidReceiptError userInfo:errorDict];
                receiptUploadCompletionHandler(nil, err);
                return;
            }

            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];

            if (error) {
                NSDictionary *errorDict = @{ NSLocalizedDescriptionKey : @"JSON parse failure", NSUnderlyingErrorKey: error};
                NSError *err = [[NSError alloc] initWithDomain:kReceiptValidationErrorDomain code:PsiphonReceiptValidationJSONParseError userInfo:errorDict];
                receiptUploadCompletionHandler(nil, err);
                return;
            }

            receiptUploadCompletionHandler(dict, nil);
        }
        // NOTE strong self reference here is used on purpose, self doesn't have a
        // reference to the completion handler block and we want to make sure
        // the object is alive while the data task is being performed.
        [self cleanup];
    }];

    [postDataTask resume];
}

-(void)openProducerStream:(id)object {
    [self.producerStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.producerStream open];

    while (![[NSThread currentThread] isCancelled]) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }

    [self.producerStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)cleanup {
    if (self.bufferOnHeap) {
        free(self.bufferOnHeap);
        self.bufferOnHeap = NULL;
    }
    self.buffer = NULL;
    self.bufferOffset = 0;
    self.bufferLimit  = 0;
    self.bodyPrefixData = nil;
    if (self.producerStream != nil) {
        self.producerStream.delegate = nil;
        [self.producerStream close];
        self.producerStream = nil;
    }
    self.consumerStream = nil;
    if (self.base64encodedFileStream != nil) {
        [self.base64encodedFileStream close];
        self.base64encodedFileStream = nil;
    }
    self.bodySuffixData = nil;
    if (self.streamThread && !self.streamThread.isCancelled) {
        [self.streamThread cancel];
    }
}


- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
// An NSStream delegate callback that's called when events happen on our
// network stream.
#pragma unused(aStream)
    assert(aStream == self.producerStream);

    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
        } break;
        case NSStreamEventHasBytesAvailable: {
            assert(NO);     // should never happen for the output stream
        } break;
        case NSStreamEventHasSpaceAvailable: {
            // Check to see if we've run off the end of our buffer.  If we have,
            // work out the next buffer of data to send.

            if (self.bufferOffset == self.bufferLimit) {

                // See if we're transitioning from the prefix to the file data.
                // If so, allocate a file buffer.

                if (self.bodyPrefixData != nil) {
                    self.bodyPrefixData = nil;

                    assert(self.bufferOnHeap == NULL);
                    self.bufferOnHeap = malloc(kPostBufferSize);
                    assert(self.bufferOnHeap != NULL);
                    self.buffer = self.bufferOnHeap;

                    self.bufferOffset = 0;
                    self.bufferLimit  = 0;
                }

                // If we still have file data to send, read the next chunk.

                if (self.base64encodedFileStream != nil) {
                    NSInteger   bytesRead;

                    // Calculate max length to read from the file at once based on the result buffer length
                    // Each 3 bytes chunk gets converted to 4 bytes and we want to read in n*3 chunks until we reach the file's end
                    NSUInteger maxReadLen = (NSUInteger) (kPostBufferSize / 4) * 3;
                    bytesRead = [self.base64encodedFileStream read:self.bufferOnHeap maxLength:maxReadLen];

                    if (bytesRead == -1) {
                        [self cleanup];
                    } else if (bytesRead != 0) {
                        self.bufferOffset = 0;
                        self.bufferLimit  = bytesRead;
                    } else {
                        // If we hit the end of the file, transition to sending the
                        // suffix.

                        [self.base64encodedFileStream close];
                        self.base64encodedFileStream = nil;

                        assert(self.bufferOnHeap != NULL);
                        free(self.bufferOnHeap);
                        self.bufferOnHeap = NULL;
                        self.buffer       = [self.bodySuffixData bytes];

                        self.bufferOffset = 0;
                        self.bufferLimit  = [self.bodySuffixData length];
                    }
                }

                // If we've failed to produce any more data, we close the stream
                // to indicate to NSURLConnection that we're all done.  We only do
                // this if producerStream is still valid to avoid running it in the
                // file read error case.

                if ( (self.bufferOffset == self.bufferLimit) && (self.producerStream != nil) ) {
                    // We set our delegate callback to nil because we don't want to
                    // be called anymore for this stream.  However, we can't
                    // remove the stream from the runloop (doing so prevents the
                    // URL from ever completing) and nor can we nil out our
                    // stream reference (that causes all sorts of wacky crashes).
                    //
                    // +++ Need bug numbers for these problems.
                    self.producerStream.delegate = nil;
                    [self.producerStream close];

                }
            }

            // Send the next chunk of data in our buffer.

            if (self.bufferOffset != self.bufferLimit) {
                NSInteger   bytesWritten;
                bytesWritten = [self.producerStream write:&self.buffer[self.bufferOffset] maxLength:self.bufferLimit - self.bufferOffset];
                if (bytesWritten <= 0) {
                    [self cleanup];
                } else {
                    self.bufferOffset += bytesWritten;
                }
            }
        } break;
        case NSStreamEventErrorOccurred: {
            NSLog(@"producer stream error %@", [aStream streamError]);
            [self cleanup];
        } break;
        case NSStreamEventEndEncountered: {
            assert(NO);     // should never happen for the output stream
        } break;
        default: {
            assert(NO);
        } break;
    }
}

@end
