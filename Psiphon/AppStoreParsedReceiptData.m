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
#import "AppStoreParsedReceiptData.h"
#import "SharedConstants.h"
#import "NSDate+Comparator.h"
#import "Logging.h"
#import "PsiFeedbackLogger.h"
#import "NSDate+PSIDateExtension.h"

PsiFeedbackLogType const AppReceipt = @"AppReceipt";

// From https://developer.apple.com/library/ios/releasenotes/General/ValidateAppStoreReceipt/Chapters/ReceiptFields.html#//apple_ref/doc/uid/TP40010573-CH106-SW1
// Note: If a previous subscription period in the receipt has the value “true” for either
//       the is_trial_period or the is_in_intro_offer_period key, the user is not eligible
//       for a free trial or introductory price within that subscription group.

NSInteger const ReceiptASN1TypeBundleIdentifier = 2;
NSInteger const ReceiptASN1TypeInAppPurchaseReceipt = 17;
NSInteger const ReceiptASN1TypeProductIdentifier = 1702;
NSInteger const ReceiptASN1TypeTransactionID = 1703;
NSInteger const ReceiptASN1TypePurchaseDate =  1704;
NSInteger const ReceiptASN1TypeOriginalTransactionID = 1705;
NSInteger const ReceiptASN1TypeSubscriptionExpirationDate = 1708;
NSInteger const ReceiptASN1TypeIsInIntroOfferPeriod = 1719;
NSInteger const ReceiptASN1TypeWebOrderLineItemID = 1711;
NSInteger const ReceiptASN1TypeCancellationDate = 1712;

static intmax_t
asn__integer_convert(const uint8_t *b, const uint8_t *end) {
    uintmax_t value;

    /* Perform the sign initialization */
    /* Actually value = -(*b >> 7); gains nothing, yet unreadable! */
    if((*b >> 7)) {
        value = (uintmax_t)(-1);
    } else {
        value = 0;
    }

    /* Conversion engine */
    for(; b < end; b++) {
        value = (value << 8) | *b;
    }

    return value;
}

int
asn_INTEGER2imax(const INTEGER_t *iptr, intmax_t *lptr) {
    uint8_t *b, *end;
    size_t size;

    /* Sanity checking */
    if(!iptr || !iptr->buf || !lptr) {
        errno = EINVAL;
        return -1;
    }

    /* Cache the begin/end of the buffer */
    b = iptr->buf;    /* Start of the INTEGER buffer */
    size = iptr->size;
    end = b + size;    /* Where to stop */

    if(size > sizeof(intmax_t)) {
        uint8_t *end1 = end - 1;
        /*
         * Slightly more advanced processing,
         * able to process INTEGERs with >sizeof(intmax_t) bytes
         * when the actual value is small, e.g. for intmax_t == int32_t
         * (0x0000000000abcdef INTEGER would yield a fine 0x00abcdef int32_t)
         */
        /* Skip out the insignificant leading bytes */
        for(; b < end1; b++) {
            switch(*b) {
                case 0x00: if((b[1] & 0x80) == 0) continue; break;
                case 0xff: if((b[1] & 0x80) != 0) continue; break;
            }
            break;
        }

        size = end - b;
        if(size > sizeof(intmax_t)) {
            /* Still cannot fit the sizeof(intmax_t) */
            errno = ERANGE;
            return -1;
        }
    }

    /* Shortcut processing of a corner case */
    if(end == b) {
        *lptr = 0;
        return 0;
    }

    *lptr = asn__integer_convert(b, end);
    return 0;
}

static NSString* ASN1ReadUTF8String(const uint8_t *bytes, long length) {
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

static NSString* ASN1ReadIA5SString(const uint8_t *bytes, long length) {
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

static intmax_t ASN1ReadInteger(const uint8_t *bytes, long length) {
    intmax_t parsed = 0;
    INTEGER_t *asn1Integer = NULL;

    asn_dec_rval_t rval = ber_decode(0, &asn_DEF_INTEGER, (void **)&asn1Integer, bytes, length);

    int result = asn_INTEGER2imax(asn1Integer, &parsed);

    if (result != 0) {
        [NSException raise:NSGenericException format:@"Failed to parse ASN1 Integer"];
        exit(1);
    }

    if (rval.code == RC_OK) {
        ASN_STRUCT_FREE(asn_DEF_INTEGER, asn1Integer);
    }

    return parsed;
}


// TODO: Local receipt does not contains `is_trial_period` field, it is only accessible by
// sending the receipt to Apple.
// https://developer.apple.com/library/archive/releasenotes/General/ValidateAppStoreReceipt/Chapters/ReceiptFields.html#//apple_ref/doc/uid/TP40010573-CH106-SW25
// Determining eligibility: https://developer.apple.com/documentation/storekit/in-app_purchase/implementing_introductory_offers_in_your_app
@implementation AppStoreParsedReceiptData

- (instancetype)initWithASN1Data:(NSData*)asn1Data {
    self = [super init];
    if (self) {
        NSMutableArray<AppStoreParsedIAP *> *mutablePurchases = [NSMutableArray array];
        
        // Explicit casting to avoid errors when compiling as Objective-C++
        [AppStoreParsedReceiptData enumerateReceiptAttributes:(const uint8_t*)asn1Data.bytes length:asn1Data.length usingBlock:^(NSData *data, long type) {
            switch (type) {
                case ReceiptASN1TypeBundleIdentifier:
                    self->_bundleIdentifier = ASN1ReadUTF8String(data.bytes, data.length);
                    break;
                case ReceiptASN1TypeInAppPurchaseReceipt: {
                    AppStoreParsedIAP *iapPurchase = [[AppStoreParsedIAP alloc]
                                                       initWithASN1Data:data];
                    [mutablePurchases addObject: iapPurchase];
                }
                default:
                    break;
            }
        }];
        
        self->_inAppPurchases = mutablePurchases;
    }
    return self;
}

+ (AppStoreParsedReceiptData *_Nullable)parseReceiptData:(NSData *_Nonnull)data {
    AppStoreParsedReceiptData *receipt = nil;
    SignedData_t * signedData = NULL;
    
    void *bytes = (void*) [data bytes];
    size_t length = (size_t)[data length];
    
    if(length == 0) {
        return nil;
    }
    
    asn_dec_rval_t rval = ber_decode(0, &asn_DEF_SignedData, (void **)&signedData, bytes, length);

    if (rval.code == RC_OK) {
        int signedDataSize = signedData->content.contentInfo.contentData.size;
        uint8_t* signedDataBuf = signedData->content.contentInfo.contentData.buf;

       receipt = [[AppStoreParsedReceiptData alloc] initWithASN1Data:[NSData dataWithBytesNoCopy:signedDataBuf length:signedDataSize freeWhenDone:NO ]];
    }
    
    if (signedData != NULL) {
        ASN_STRUCT_FREE(asn_DEF_SignedData, signedData);
    }
    
    return receipt;
}

+ (void)enumerateReceiptAttributes:(const uint8_t*)p length:(long)tlength
                        usingBlock:(void (^)(NSData *_Nonnull data, long type))block
{
    ReceiptAttributes_t * receiptAttributes = NULL;
    asn_dec_rval_t rval = ber_decode(0, &asn_DEF_ReceiptAttributes,
                                     (void **)&receiptAttributes, p, tlength);
    if (rval.code == RC_OK) {
        for(int i = 0; i < receiptAttributes->list.count; i++) {
            ReceiptAttribute_t *receiptAttr = receiptAttributes->list.array[i];
            if (receiptAttr->value.size) {
                NSData *_Nonnull nonCopied = [NSData dataWithBytesNoCopy:receiptAttr->value.buf
                                                                  length:receiptAttr->value.size
                                                            freeWhenDone:NO];
                block(nonCopied, receiptAttr->type);
            }
        }
    }
    if(receiptAttributes != NULL) {
        ASN_STRUCT_FREE(asn_DEF_ReceiptAttributes, receiptAttributes);
    }
}

@end


@implementation AppStoreParsedIAP

- (instancetype)initWithASN1Data:(NSData *_Nonnull)asn1Data {
    self = [super init];
    if (self) {
        // Initializes subscription-only fields to nil.
        self->_webOrderLineItemID = nil;
        self->_expiresDate = nil;
        self->_cancellationDate = nil;
        
        [AppStoreParsedReceiptData enumerateReceiptAttributes:(const uint8_t*)asn1Data.bytes
                                                 length:asn1Data.length
                                             usingBlock:^(NSData *data, long type)
         {
            const uint8_t *p = (const uint8_t*)data.bytes;
            const NSUInteger length = data.length;
            switch (type) {
                case ReceiptASN1TypeProductIdentifier:
                    self->_productIdentifier = ASN1ReadUTF8String(p, length);
                    break;
                case ReceiptASN1TypeTransactionID:
                    self->_transactionID = ASN1ReadUTF8String(p, length);
                    break;
                case ReceiptASN1TypeOriginalTransactionID:
                    self->_originalTransactionID = ASN1ReadUTF8String(p, length);
                    break;
                case ReceiptASN1TypePurchaseDate: {
                    NSString *string = ASN1ReadIA5SString(p, length);
                    self->_purchaseDate = [NSDate fromRFC3339String:string];
                    break;
                }
                case ReceiptASN1TypeSubscriptionExpirationDate: {
                    NSString *string = ASN1ReadIA5SString(p, length);
                    self->_expiresDate = [NSDate fromRFC3339String:string];
                    break;
                }
                case ReceiptASN1TypeCancellationDate: {
                    NSString *string = ASN1ReadIA5SString(p, length);
                    self->_cancellationDate = [NSDate fromRFC3339String:string];
                    break;
                }
                case ReceiptASN1TypeWebOrderLineItemID: {
                    intmax_t webOrderLineItemID = ASN1ReadInteger(p, length);
                    self->_webOrderLineItemID = [NSString stringWithFormat:@"%jd",
                                                 webOrderLineItemID];
                    break;
                }
                case ReceiptASN1TypeIsInIntroOfferPeriod: {
                    intmax_t is_in_intro_period = ASN1ReadInteger(p, length);
                    self->_isInIntroPeriod = [[NSNumber numberWithLongLong: is_in_intro_period]
                                              boolValue];
                    break;
                }
            }
        }];
    }
    return self;
}

@end
