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

FOUNDATION_EXPORT NSString *const SubscriptionReceiptInputStreamError;
FOUNDATION_EXPORT NSString *const SubscriptionReceiptInputStreamErrorReason;

typedef NS_ENUM(NSInteger, SubscriptionReceiptInputStreamErrorCode) {
    SubscriptionReceiptInputStreamErrorUnknown = 0,
    SubscriptionReceiptInputStreamFileError = 1
};

/**
* An NSInputStream subclass which encodes input to base64 format on the fly in order to prevent
* loading the entire input into memory if there is a risk of exceeding memory threshold and/or there is a need
* to track the progress of the decoding.
*/
@interface SubscriptionReceiptInputStream : NSInputStream

@end
