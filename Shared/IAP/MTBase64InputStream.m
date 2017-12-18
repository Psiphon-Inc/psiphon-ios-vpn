// Copyright 2015 Michał Tuszyński
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "MTBase64InputStream.h"

NSString *const MTBase64InputStreamError = @"pl.iapp.base64stream.error";
NSString *const MTBase64InputStreamErrorReason = @"p.iapp.base64stream.error_reason";

static const NSUInteger kDefaultBufferLength = 684;
static const NSUInteger kDefaultLength = 513;
static const NSInteger kPaddingTable[3] = {0, 2, 1};
static const char *kBase64Table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

@interface MTBase64InputStream()

@property (strong, nonatomic) NSString *filePath;
@property (strong, nonatomic) NSFileHandle *fileHandle;
@property (assign, nonatomic) NSUInteger inputBytes;
@property (assign, nonatomic) NSUInteger index;
@property (assign, nonatomic) NSInteger padding;
@property (unsafe_unretained, nonatomic) unsigned char *temporaryBuffer;
@property (assign) id<NSStreamDelegate> delegate;
@property (readwrite, atomic) NSStreamStatus streamStatus;
@property (copy) NSError *streamError;

@end

@implementation MTBase64InputStream

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
        self.streamError = [NSError errorWithDomain:MTBase64InputStreamError
                                               code:MTBase64InputStreamFileError
                                           userInfo:@{MTBase64InputStreamErrorReason : reason}];
        self.streamStatus = NSStreamStatusError;
        [self notifyDelegateWithEvent:NSStreamEventErrorOccurred];
        return;
    }
    
    //Initialize buffers and buffer pointer (index)
    self.index = 0;
    self.temporaryBuffer = malloc(3 * sizeof(unsigned char));
    self.inputBytes = [attributes[NSFileSize] unsignedIntegerValue];
    self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.filePath];
    self.padding = kPaddingTable[self.inputBytes % 3];
    self.streamStatus = NSStreamStatusOpen;
    [self notifyDelegateWithEvent:NSStreamEventOpenCompleted];
    
    //Handle case when stream is opened with an empty file
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
    if (self.temporaryBuffer) free(self.temporaryBuffer);
    self.inputBytes = 0;
    self.padding = 0;
    self.streamStatus = NSStreamStatusClosed;
}

- (BOOL)hasBytesAvailable {
    return (self.index < self.inputBytes + self.padding);
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
    NSAssert(sizeof(buffer) / sizeof(uint8_t) % 4 == 0, @"Buffer size not dividable by 4");
    NSAssert(len % 3 == 0, @"Max length must be divisable by 3");
    if (self.streamStatus != NSStreamStatusOpen) return -1;
    
    //Update state, file offset and read a chunk of data
    self.streamStatus = NSStreamStatusReading;
    [self.fileHandle seekToFileOffset:self.index];
    NSData *data = [self.fileHandle readDataOfLength:len];
    
    //Declare any necessary variables
    NSUInteger bytesRead = data.length;
    NSInteger bytesToRead = 0;
    NSUInteger bufferIndex = 0;
    NSUInteger stop = self.index + bytesRead;
    NSUInteger dataIndex = 0; //TODO Is this variable necessary?
    while (self.index < stop) {
        //Read 3 or less bytes from the chunk
        bytesToRead = MIN(3, stop - self.index); //Either 3 or remaining bytes
        [data getBytes:self.temporaryBuffer range:NSMakeRange(dataIndex, bytesToRead)];
        dataIndex += bytesToRead;
        unsigned char byte1 = self.temporaryBuffer[0], byte2 = self.temporaryBuffer[1], byte3 = self.temporaryBuffer[2];
        
        //Read 3 bytes, append
        if (bytesToRead == 3) {
            buffer[bufferIndex]       = (uint8_t) kBase64Table[(byte1 >> 2) & 0x3F];
            buffer[bufferIndex + 1]   = (uint8_t) kBase64Table[((byte1 << 4) & 0x30) | ((byte2 >> 4) & 0x0F)];
            buffer[bufferIndex + 2]   = (uint8_t) kBase64Table[((byte2 << 2 & 0x3C)) | ((byte3 >> 6) & 0x03)];
            buffer[bufferIndex + 3]   = (uint8_t) kBase64Table[byte3 & 0x3F];
            bufferIndex += 4;
        } else {
            switch (bytesToRead) {
                case 2:
                    buffer[bufferIndex]       = (uint8_t) kBase64Table[(byte1 >> 2) & 0x3F];
                    buffer[bufferIndex + 1]   = (uint8_t) kBase64Table[((byte1 << 4) & 0x30) | ((byte2 >> 4) & 0x0F)];
                    buffer[bufferIndex + 2]   = (uint8_t) kBase64Table[(byte2 << 2) & 0x3C];
                    bufferIndex += 3;
                    break;
                case 1:
                    byte2 = 0;
                    buffer[bufferIndex]       = (uint8_t) kBase64Table[(byte1 >> 2) & 0x3F];
                    buffer[bufferIndex + 1]   = (uint8_t) kBase64Table[((byte1 << 4) & 0x30) | ((byte2 >> 4) & 0x0F)];
                    bufferIndex += 2;
                    break;
            }
        }
        //Mark file offset pointer
        self.index += bytesToRead;
        
        //Check if we reached the end of the file and padding must be appended
        if (self.index >= self.inputBytes) {
            for (NSInteger j = 0; j < self.padding; j++) {
                buffer[bufferIndex] = '=';
                bufferIndex++;
            }
            self.index += self.padding;
        }
    }
    
    //Notify delegate, update state and return number of read bytes from the file
    if (![self hasBytesAvailable]) {
        self.streamStatus = NSStreamStatusAtEnd;
        [self notifyDelegateWithEvent:NSStreamEventEndEncountered];
    } else {
        self.streamStatus = NSStreamStatusOpen;
    }
    return bufferIndex;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len {
    *len = kDefaultLength;
    *buffer = malloc(kDefaultBufferLength * sizeof(uint8_t));
    return YES;
}

#pragma mark - Internal

- (void)notifyDelegateWithEvent:(NSStreamEvent)event {
    //NSStreamDelegate is an informal protocol, so we need to check if it responds
    //to the selector
    if (![self.delegate respondsToSelector:@selector(stream:handleEvent:)]) return;
    [self.delegate stream:self handleEvent:event];
    
}

@end
