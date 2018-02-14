//
//  RMAppReceipt.h
//  RMStore
//
//  Created by Hermes on 10/12/13.
//  Copyright (c) 2013 Robot Media. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
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

@class RMAppReceiptIAP;

/** Represents the app receipt.
 */
__attribute__((availability(ios,introduced=7.0)))

@interface RMAppReceipt : NSObject

/** The app’s bundle identifier. 
 
 This corresponds to the value of CFBundleIdentifier in the Info.plist file.
 */
@property (nonatomic, strong, readonly) NSString *bundleIdentifier;

/** The bundle identifier as data, as contained in the receipt. Used to verifiy the receipt's hash.
 @see verifyReceiptHash
 */
@property (nonatomic, strong, readonly) NSData *bundleIdentifierData;

/** An opaque value used as part of the SHA-1 hash.
 */
@property (nonatomic, strong, readonly) NSData *opaqueValue;

/** A SHA-1 hash, used to validate the receipt.
 */
@property (nonatomic, strong, readonly) NSData *receiptHash;

/** Array of in-app purchases contained in the receipt.
 @see RMAppReceiptIAP
 */
@property (nonatomic, strong, readonly) NSDictionary *inAppSubscriptions;


/** Returns an initialized app receipt from the given data.
 @param asn1Data ASN1 data
 @return An initialized app receipt from the given data.
 */
- (instancetype)initWithASN1Data:(NSData*)asn1Data NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/** Returns wheter the receipt hash corresponds to the device's GUID by calcuting the expected hash using the GUID, bundleIdentifierData and opaqueValue.
 @return YES if the hash contained in the receipt corresponds to the device's GUID, NO otherwise.
 */
- (BOOL)verifyReceiptHash;

/**
 Returns the app receipt contained in the bundle, if any and valid. Extracts the receipt in ASN1 from the PKCS #7 container, and then parses the ASN1 data into a RMAppReceipt instance. It will also verify that the signature of the receipt is valid.
 @return The app receipt contained in the bundle, or nil if there is no receipt or if it is invalid or not verified.
 @see refreshReceipt
 @see setAppleRootCertificateURL:
 */
+ (RMAppReceipt*)bundleReceipt;

/**
 Sets the url of the Apple Root certificate that will be used to verifiy the signature of the bundle receipt. If none is provided, the resource AppleIncRootCertificate.cer will be used. If no certificate is available, no signature verification will be performed.
 @param url The url of the Apple Root certificate.
 */
+ (void)setAppleRootCertificateURL:(NSURL*)url;

/*
 Get subscription expiration date for give product ID
 */
- (NSDate*)expirationDateForProduct:(NSString*)productIdentifier;

@end

/** Represents an in-app purchase in the app receipt.
 */
@interface RMAppReceiptIAP : NSObject

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
