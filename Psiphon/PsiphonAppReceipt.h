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
#import "SignedData.h"
#import "ReceiptAttributes.h"
#import "ReceiptAttribute.h"
#import "UTF8String.h"
#import "IA5String.h"


@class PsiphonAppReceipt;

@interface PsiphonAppReceipt : NSObject

/** The app’s bundle identifier.
 
 This corresponds to the value of CFBundleIdentifier in the Info.plist file.
 */
@property (nonatomic, strong, readonly) NSString *bundleIdentifier;

@property (nonatomic, strong, readonly) NSDictionary *inAppSubscriptions;


/** Returns an initialized app receipt from the given data.
 @param asn1Data ASN1 data
 @return An initialized app receipt from the given data.
 */
- (instancetype)initWithASN1Data:(NSData*)asn1Data NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;


/**
 Returns the app receipt contained in the bundle, if any and valid. Extracts the receipt in ASN1 from the PKCS #7 container, and then parses the ASN1 data into a RMAppReceipt instance.
 */
+ (PsiphonAppReceipt*)bundleReceipt;

@end

/** Represents an in-app purchase in the app receipt.
 */
@interface PsiphonAppReceiptIAP : NSObject

/** The product identifier of the item that was purchased. This value corresponds to the productIdentifier property of the SKPayment object stored in the transaction’s payment property.
 */
@property (nonatomic, strong, readonly) NSString *productIdentifier;

/**
 The expiration date for the subscription.
 
 Only present for auto-renewable subscription receipts.
 */
@property (nonatomic, strong, readonly) NSDate *subscriptionExpirationDate;

/** For a transaction that was canceled by Apple customer support, the date of the cancellation.
 */
@property (nonatomic, strong, readonly) NSDate *cancellationDate;

/** Returns an initialized in-app purchase from the given data.
 @param asn1Data ASN1 data
 @return An initialized in-app purchase from the given data.
 */
- (instancetype)initWithASN1Data:(NSData*)asn1Data NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end
