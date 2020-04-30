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

/** Represents an in-app purchase in the app receipt.
 */
@interface AppStoreParsedIAP : NSObject

/** The product identifier of the item that was purchased. This value corresponds to the productIdentifier property of the SKPayment object stored in the transaction’s payment property.
 */
@property (nonatomic, strong, readonly) NSString *_Nonnull productIdentifier;

@property (nonatomic, strong, readonly) NSString *_Nonnull transactionID;

@property (nonatomic, strong, readonly) NSString *_Nonnull originalTransactionID;

@property (nonatomic, strong, readonly) NSDate *_Nonnull purchaseDate;

/**
 The expiration date for the subscription.
 
 Only present for auto-renewable subscription receipts.
 */
@property (nonatomic, strong, readonly) NSDate *_Nullable expiresDate;

/** For a transaction that was canceled by Apple customer support, the date of the cancellation.
 */
@property (nonatomic, strong, readonly) NSDate *_Nullable cancellationDate;

/** True if this transaction is in intro period, False otherwise.
 */
@property (nonatomic, readonly) BOOL isInIntroPreiod;

- (instancetype _Nonnull)initWithASN1Data:(NSData *_Nonnull)asn1Data NS_DESIGNATED_INITIALIZER;

- (instancetype _Nonnull)init NS_UNAVAILABLE;

@end


@interface AppStoreParsedReceiptData : NSObject

/** The app’s bundle identifier.
 
 This corresponds to the value of CFBundleIdentifier in the Info.plist file.
 */
@property (nonatomic, strong, readonly) NSString *_Nonnull bundleIdentifier;

/** Set of in-app purchases. Contains subscriptions and other consumable transactions present in the receipt file.
 This corresponds to the values in the "in_app" field of of JSON object retrieved from AppStore receipt verify servers.
 Returned array is empty if there are no purchases recorded in the receipt.
 */
@property (nonatomic, strong, readonly) NSArray<AppStoreParsedIAP *> *_Nonnull inAppPurchases;

/** Returns an initialized app receipt from the given data.
 @param asn1Data ASN1 data
 @return An initialized app receipt from the given data.
 */
- (instancetype _Nonnull)initWithASN1Data:(NSData *_Nonnull)asn1Data NS_DESIGNATED_INITIALIZER;

- (instancetype _Nonnull)init NS_UNAVAILABLE;

/**
 Parses receipt pointed to by `receiptURL` and returns  `AppStoreParsedReceiptData` object created from the parsed data.
 */
+ (AppStoreParsedReceiptData *_Nullable)parseReceiptData:(NSData *_Nonnull)receiptURL;

@end
