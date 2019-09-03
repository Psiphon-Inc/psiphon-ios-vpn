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

#import <UIKit/UIKit.h>
#import "PsiphonAppReceipt.h"
#import "SharedConstants.h"
#import "NSDate+Comparator.h"
#import "IAPStoreHelper.h"
#import "Logging.h"
#import "PsiFeedbackLogger.h"

PsiFeedbackLogType const AppReceipt = @"AppReceipt";

// From https://developer.apple.com/library/ios/releasenotes/General/ValidateAppStoreReceipt/Chapters/ReceiptFields.html#//apple_ref/doc/uid/TP40010573-CH106-SW1
// Note: If a previous subscription period in the receipt has the value “true” for either
//       the is_trial_period or the is_in_intro_offer_period key, the user is not eligible
//       for a free trial or introductory price within that subscription group.

NSInteger const PsiphonAppReceiptASN1TypeBundleIdentifier = 2;
NSInteger const PsiphonAppReceiptASN1TypeInAppPurchaseReceipt = 17;
NSInteger const PsiphonAppReceiptASN1TypeProductIdentifier = 1702;
NSInteger const PsiphonAppReceiptASN1TypeSubscriptionExpirationDate = 1708;
NSInteger const PsiphonAppReceiptASN1TypeIsInIntroOfferPeriod = 1719;
NSInteger const PsiphonAppReceiptASN1TypeCancellationDate = 1712;

static NSString* PsiphonASN1ReadUTF8String(const uint8_t *bytes, long length) {
    UTF8String_t *utf8String = NULL;
    NSString *retString;
    
    asn_dec_rval_t rval = ber_decode(0, &asn_DEF_UTF8String, (void **)&utf8String, bytes, length);
    
    if (rval.code == RC_OK) {
        retString = [[NSString alloc]initWithBytes:utf8String->buf length:utf8String->size encoding:NSUTF8StringEncoding];
    }
    
    if (utf8String != NULL) {
        ASN_STRUCT_FREE(asn_DEF_UTF8String, utf8String);
    }
    
    return retString;
}

static NSString* PsiphonASN1ReadIA5SString(const uint8_t *bytes, long length) {
    IA5String_t *ia5String = NULL;
    NSString *retString;
    
    asn_dec_rval_t rval = ber_decode(0, &asn_DEF_IA5String, (void **)&ia5String, bytes, length);
    
    if (rval.code == RC_OK) {
        retString = [[NSString alloc]initWithBytes:ia5String->buf length:ia5String->size encoding:NSUTF8StringEncoding];
    }
    
    if (ia5String != NULL) {
        ASN_STRUCT_FREE(asn_DEF_IA5String, ia5String);
    }
    
    return retString;
}

static long PsiphonASN1ReadInteger(const uint8_t *bytes, long length) {
    long parsed = 0;
    INTEGER_t *asn1Integer = NULL;

    asn_dec_rval_t rval = ber_decode(0, &asn_DEF_INTEGER, (void **)&asn1Integer, bytes, length);

    int result = asn_INTEGER2long(asn1Integer, &parsed);

    if (result != 0) {
        [NSException raise:NSGenericException format:@"Failed to parse ASN1 Integer"];
        exit(1);
    }

    if (rval.code == RC_OK) {
        ASN_STRUCT_FREE(asn_DEF_INTEGER, asn1Integer);
    }

    return parsed;
}

@implementation PsiphonAppReceipt

- (instancetype)initWithASN1Data:(NSData*)asn1Data {
    if (self = [super init]) {
        NSMutableDictionary *subscriptions = [[NSMutableDictionary alloc] init];
        __block BOOL hasBeenInIntroPeriod = FALSE;

        // Explicit casting to avoid errors when compiling as Objective-C++
        [PsiphonAppReceipt enumerateReceiptAttributes:(const uint8_t*)asn1Data.bytes length:asn1Data.length usingBlock:^(NSData *data, long type) {
            switch (type) {
                case PsiphonAppReceiptASN1TypeBundleIdentifier:
                    _bundleIdentifier = PsiphonASN1ReadUTF8String(data.bytes, data.length);
                    break;
                case PsiphonAppReceiptASN1TypeInAppPurchaseReceipt: {
                    @autoreleasepool {
                        PsiphonAppReceiptIAP *iapReceipt = [[PsiphonAppReceiptIAP alloc] initWithASN1Data:data];
                        if(iapReceipt.cancellationDate) {
                            iapReceipt = nil;
                            break;
                        }
                        // sanity check
                        if(iapReceipt.subscriptionExpirationDate == nil || iapReceipt.productIdentifier == nil) {
                            iapReceipt = nil;
                            break;
                        }

                        hasBeenInIntroPeriod = hasBeenInIntroPeriod || iapReceipt.isInIntroPreiod;

                        NSDate *latestExpirationDate = subscriptions[kLatestExpirationDate];
                        
                        if (!latestExpirationDate || [latestExpirationDate before:iapReceipt.subscriptionExpirationDate]) {
                            subscriptions[kLatestExpirationDate] = [iapReceipt.subscriptionExpirationDate copy];
                            subscriptions[kProductId] = [iapReceipt.productIdentifier copy];
                        }
                        iapReceipt = nil;
                    }
                }
                default:
                    break;
            }
        }];


        NSNumber *boolHasBeenInIntroPeriod = [NSNumber numberWithBool:hasBeenInIntroPeriod];
        subscriptions[kHasBeenInIntroPeriod] = boolHasBeenInIntroPeriod;

        [PsiFeedbackLogger infoWithType:AppReceipt json:@{@"HasBeenInIntroPeriod": boolHasBeenInIntroPeriod}];

        NSNumber *appReceiptFileSize;
        [[NSBundle mainBundle].appStoreReceiptURL getResourceValue:&appReceiptFileSize
                                                            forKey:NSURLFileSizeKey
                                                             error:nil];
        subscriptions[kAppReceiptFileSize] = appReceiptFileSize;

        _inAppSubscriptions = (NSDictionary*)subscriptions;
    }
    return self;
}

+ (PsiphonAppReceipt*)bundleReceipt {
    PsiphonAppReceipt *receipt = nil;
    SignedData_t * signedData = NULL;

    NSURL *URL = [NSBundle mainBundle].appStoreReceiptURL;
    NSString *path = URL.path;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil]) {
        return nil;
    }
    
    NSData *data = [NSData dataWithContentsOfURL:URL];
    
    void *bytes = (void*) [data bytes];
    size_t length = (size_t)[data length];
    
    if(length == 0) {
        return nil;
    }
    
    asn_dec_rval_t rval = ber_decode(0, &asn_DEF_SignedData, (void **)&signedData, bytes, length);

    if (rval.code == RC_OK) {
        int signedDataSize = signedData->content.contentInfo.contentData.size;
        uint8_t* signedDataBuf = signedData->content.contentInfo.contentData.buf;

       receipt = [[PsiphonAppReceipt alloc] initWithASN1Data:[NSData dataWithBytesNoCopy:signedDataBuf length:signedDataSize freeWhenDone:NO ]];
    }
    
    if (signedData != NULL) {
        ASN_STRUCT_FREE(asn_DEF_SignedData, signedData);
    }
    
    return receipt;
}

+ (void)enumerateReceiptAttributes:(const uint8_t*)p length:(long)tlength usingBlock:(void (^)(NSData *data, long type))block {
    ReceiptAttributes_t * receiptAttributes = NULL;
    asn_dec_rval_t rval = ber_decode(0, &asn_DEF_ReceiptAttributes, (void **)&receiptAttributes, p, tlength);
    if (rval.code == RC_OK) {
        for(int i = 0; i < receiptAttributes->list.count; i++) {
            ReceiptAttribute_t *receiptAttr = receiptAttributes->list.array[i];
            if (receiptAttr->value.size) {
                NSData *data = [NSData dataWithBytesNoCopy:receiptAttr->value.buf length:receiptAttr->value.size freeWhenDone:NO];
                block(data, receiptAttr->type);
            }
        }
    }
    if(receiptAttributes != NULL) {
        ASN_STRUCT_FREE(asn_DEF_ReceiptAttributes, receiptAttributes);
    }
}

+ (NSDate*)formatRFC3339String:(NSString*)string {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    });
    NSDate *date = [formatter dateFromString:string];
    return date;
}

@end


@implementation PsiphonAppReceiptIAP

- (instancetype)initWithASN1Data:(NSData*)asn1Data {
    if (self = [super init]) {
        [PsiphonAppReceipt enumerateReceiptAttributes:(const uint8_t*)asn1Data.bytes length:asn1Data.length usingBlock:^(NSData *data, long type) {
            const uint8_t *p = (const uint8_t*)data.bytes;
            const NSUInteger length = data.length;
            switch (type) {
                case PsiphonAppReceiptASN1TypeProductIdentifier:
                    _productIdentifier = PsiphonASN1ReadUTF8String(p, length);
                    break;
                case PsiphonAppReceiptASN1TypeSubscriptionExpirationDate: {
                    NSString *string = PsiphonASN1ReadIA5SString(p, length);
                    _subscriptionExpirationDate = [PsiphonAppReceipt formatRFC3339String:string];
                    break;
                }
                case PsiphonAppReceiptASN1TypeCancellationDate: {
                    NSString *string = PsiphonASN1ReadIA5SString(p, length);
                    _cancellationDate = [PsiphonAppReceipt formatRFC3339String:string];
                    break;
                }
                case PsiphonAppReceiptASN1TypeIsInIntroOfferPeriod: {
                    long is_in_intro_period = PsiphonASN1ReadInteger(p, length);
                    _isInIntroPreiod = [[NSNumber numberWithLong: is_in_intro_period] boolValue];
                    break;
                }
            }
        }];
    }
    return self;
}

@end
