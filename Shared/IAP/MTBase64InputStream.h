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

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const MTBase64InputStreamError;
FOUNDATION_EXPORT NSString *const MTBase64InputStreamErrorReason;

typedef NS_ENUM(NSInteger, MTBase64InputStreamErrorCode) {
    MTBase64InputStreamErrorUnknown = 0,
    MTBase64InputStreamFileError = 1
};

/**
* An NSInputStream subclass which encodes input to base64 format on the fly in order to prevent
* loading the entire input into memory if there is a risk of exceeding memory threshold and/or there is a need
* to track the progress of the decoding.
*/
@interface MTBase64InputStream : NSInputStream

@end
