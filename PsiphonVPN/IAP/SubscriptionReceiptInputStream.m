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

#import "SubscriptionReceiptInputStream.h"

NSString *const SubscriptionReceiptInputStreamError = @"ca.psiphon.base64stream.error";
NSString *const SubscriptionReceiptInputStreamErrorReason = @"ca.psiphon.base64stream.error_reason";

static const NSUInteger kDefaultBufferLength = 684;
static const NSUInteger kDefaultLength = 513;

@interface SubscriptionReceiptInputStream()

@property (strong, nonatomic) NSString *filePath;
@property (strong, nonatomic) NSFileHandle *fileHandle;
@property (assign, nonatomic) NSUInteger inputLength;
@property (assign, nonatomic) NSUInteger index;
@property (assign) id<NSStreamDelegate> delegate;
@property (readwrite, atomic) NSStreamStatus streamStatus; // must be here
@property (copy) NSError *streamError; // must be here
@property (assign, nonatomic) BOOL bodyWritten;

@property (assign, nonatomic) BOOL prefixWritten;
@property (assign, nonatomic) NSUInteger prefixIndex;
@property (strong, nonatomic) NSData *   prefixData;

@property (assign, nonatomic) BOOL suffixWritten;
@property (assign, nonatomic) NSUInteger suffixIndex;
@property (strong, nonatomic) NSData *   suffixData;

@end

@implementation SubscriptionReceiptInputStream {
    uint8_t remainingBytes[12];
    NSUInteger remainingBytesLength;
}

@synthesize streamStatus = _streamStatus;
@synthesize streamError = _streamError;
@synthesize delegate = _delegate;

#pragma mark - Init & teardown

//NSInputStream doesn't implement these initializers, since it's an abstract class. They've been defined
//in a separate implementation, therefore, we call NSObject's initializer here and omit the call to the missing
//NSInputStream's implementation
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (instancetype)initWithData:(NSData *)data {
    @throw [NSException exceptionWithName:@"Not Implemented"
                                   reason:@"This initializer isn't implemented yet, please use other ones"
                                 userInfo:nil];
}


- (instancetype)initWithFileAtPath:(NSString *)path {
    self = [super init];
    if (self) {
        _streamStatus = NSStreamStatusNotOpen;
        _filePath = path;
    }

    return self;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        NSAssert([url isFileURL], @"Expecting a file url here");
        _streamStatus = NSStreamStatusNotOpen;
        _filePath = [url path];
    }

    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        remainingBytesLength = 0;
    }
    return self;
}

#pragma clang diagnostic pop

- (void)dealloc {
    //Just in case client forgot to close the stream after using
    if (self.streamStatus == NSStreamStatusOpen) [self close];
}

#pragma mark - NSInputStream

- (void)open {
    //Check if state is valid
    NSAssert(self.streamStatus != NSStreamStatusOpening && self.streamStatus != NSStreamStatusOpen, @"Cannot open an opening or an already open stream");
    NSAssert(self.filePath, @"No file path specified");
    if (self.streamStatus == NSStreamStatusOpening || self.streamStatus == NSStreamStatusOpen) return;
    self.streamStatus = NSStreamStatusOpening;
    
    //Attempt to open the file and notify about errors
    NSError *error;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath
                                                                                error:&error];
    if (error) {
        NSString *reason = [NSString stringWithFormat:@"Cannot read attributes of provided file: %@", error];
        self.streamError = [NSError errorWithDomain:SubscriptionReceiptInputStreamError
                                               code:SubscriptionReceiptInputStreamFileError
                                           userInfo:@{SubscriptionReceiptInputStreamErrorReason : reason}];
        self.streamStatus = NSStreamStatusError;
        [self notifyDelegateWithEvent:NSStreamEventErrorOccurred];
        return;
    }
    
    //Initialize buffers and buffer pointer (index)
    self.index = 0;
    self.inputLength = [attributes[NSFileSize] unsignedIntegerValue];
    self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.filePath];
    self.streamStatus = NSStreamStatusOpen;
    [self notifyDelegateWithEvent:NSStreamEventOpenCompleted];
    self.bodyWritten = NO;

    //Initialize prefix and suffix
    self.prefixData = [@"{\"receipt-data\":\"" dataUsingEncoding:NSASCIIStringEncoding];
    self.prefixIndex = 0;
    self.prefixWritten = NO;

    self.suffixData= [@"\"}" dataUsingEncoding:NSASCIIStringEncoding];
    self.suffixIndex = 0;
    self.suffixWritten = NO;

    if (![self hasBytesAvailable]) {
        self.streamStatus = NSStreamStatusAtEnd;
        [self notifyDelegateWithEvent:NSStreamEventEndEncountered];
        return;
    }
    
    //Notify delegate about bytes to be processed
    [self notifyDelegateWithEvent:NSStreamEventHasBytesAvailable];
}

- (void)close {
    //Verify state
    NSAssert(self.streamStatus != NSStreamStatusClosed, @"Cannot close already closed stream");
    if (self.streamStatus == NSStreamStatusClosed) return;
    
    //Close file handle, clear buffer and any variables
    [self.fileHandle closeFile];
    self.inputLength = 0;
    self.streamStatus = NSStreamStatusClosed;
}

- (BOOL)hasBytesAvailable {
    return !(self.prefixWritten && self.bodyWritten && self.suffixWritten);
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len {
    if (self.streamStatus == NSStreamStatusAtEnd) {
        return 0;
    }
    //Verify state and buffer length
    NSAssert(self.streamStatus == NSStreamStatusOpen, @"Cannot read from a closed or not open stream");
    if (self.streamStatus != NSStreamStatusOpen) {
        return 0;
    }

    if (self.streamStatus != NSStreamStatusOpen) return -1;
    
    //Update state, file offset and read a chunk of data
    self.streamStatus = NSStreamStatusReading;

    if (!self.prefixWritten) {
        // Reads prefix
        NSUInteger bytesToRead = 0;
        if (self.prefixIndex < [self.prefixData length]) {

            bytesToRead = MIN([self.prefixData length] - self.prefixIndex, len);

            for (NSUInteger i = 0; i < bytesToRead; i++) {
                buffer[i] = ((uint8_t *)[self.prefixData bytes])[self.prefixIndex + i];
            }

            self.prefixIndex += bytesToRead;

            self.prefixWritten = (self.prefixIndex == [self.prefixData length]);
        }
        self.streamStatus = NSStreamStatusOpen;
        return bytesToRead;

    } else if (!self.bodyWritten) {

        NSUInteger bufferIndex = 0;

        // Writes remaining bytes from last read if any.
        if (remainingBytesLength > 0) {

            NSUInteger bytesToRead = MIN(remainingBytesLength, len);

            for (NSUInteger i = 0; i < bytesToRead; i++) {
                buffer[bufferIndex] = remainingBytes[i];
                bufferIndex++;
            }

            remainingBytesLength -= bytesToRead;

            // If the buffer is too small (could not even fit the remaining bytes) return early.
            if (remainingBytesLength > 0) {
                self.streamStatus = NSStreamStatusOpen;
                return bytesToRead;
            }
        }

        // Remaining space in buffer.
        NSUInteger bufLen = (len - bufferIndex);

        // The first largest multiple of 12 to bufLen.
        // If bufLen exactly fits the Base64 encoded bytes with no "remainder" bytes for the next buffer,
        // predictedBase64Length will be 12 bytes over bufLen.
        // Since we don't check how many bytes are left in the file, this ensures
        // that we don't sent self.bodyWritten to YES prematurely.
        NSUInteger predictedBase64Length = bufLen + (12 - (bufLen % 12));

        // Maximum number of bytes to read from file (before converting to Base64).
        NSUInteger maxBytesToRead = (predictedBase64Length * 3) / 4;

        [self.fileHandle seekToFileOffset:self.index];
        NSData *data = [self.fileHandle readDataOfLength:maxBytesToRead];
        self.index += [data length];

        NSData *base64Data = [data base64EncodedDataWithOptions:0];

        // Number of Base64 byte to copy to the buffer.
        NSUInteger base64BytesToRead = MIN([base64Data length], bufLen);
        for (NSUInteger k = 0; k < base64BytesToRead; ++k) {
            buffer[bufferIndex] = ((uint8_t *)[base64Data bytes])[k];
            bufferIndex++;
        }

        // If there are base64 bytes not written to buffer,
        // store them in remainingBytes for the next read.
        if ([base64Data length] > base64BytesToRead) {
            remainingBytesLength = [base64Data length] - base64BytesToRead;
            for (int i = 0; i < remainingBytesLength; ++i) {
                remainingBytes[i] = ((uint8_t *)[base64Data bytes])[base64BytesToRead + i];
            }
        } else {
            // We've read the whole file.
            self.bodyWritten = YES;
        }

        self.streamStatus = NSStreamStatusOpen;
        return bufferIndex;

    } else {
        // Reads suffix

        NSUInteger bytesToRead = 0;
        if (self.suffixIndex < [self.suffixData length]) {
            bytesToRead = MIN([self.suffixData length] - self.suffixIndex, len);

            for (NSUInteger i = 0; i < bytesToRead; i++) {
                buffer[i] = ((uint8_t *)[self.suffixData bytes])[self.suffixIndex + i];
            }

            self.suffixIndex += bytesToRead;
        }

        //Notify delegate, update state and return number of read bytes from the file
        if (self.suffixIndex >= [self.suffixData length]) {
            self.suffixWritten = YES;
            self.streamStatus = NSStreamStatusAtEnd;
            [self notifyDelegateWithEvent:NSStreamEventEndEncountered];
        } else {
            self.streamStatus = NSStreamStatusOpen;
        }

        return bytesToRead;
    }
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len {
    if (!self.prefixWritten) {
        *len = [self.prefixData length];
        *buffer = malloc([self.prefixData length] * sizeof(uint8_t));
    } else if (!self.bodyWritten) {
        *len = kDefaultLength;
        *buffer = malloc(kDefaultBufferLength * sizeof(uint8_t));
    } else {
        *len = [self.suffixData length];
        *buffer = malloc([self.suffixData length] * sizeof(uint8_t));
    }
    return YES;
}

#pragma mark - Internal

- (void)notifyDelegateWithEvent:(NSStreamEvent)event {
    //NSStreamDelegate is an informal protocol, so we need to check if it responds
    //to the selector
    if (![self.delegate respondsToSelector:@selector(stream:handleEvent:)]) return;
    [self.delegate stream:self handleEvent:event];
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode {
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode {
}

- (nullable id)propertyForKey:(NSStreamPropertyKey)key {
    return [super propertyForKey:key];
}

- (BOOL)setProperty:(nullable id)property forKey:(NSStreamPropertyKey)key {
    return [super setProperty:property forKey:key];
}

@end
