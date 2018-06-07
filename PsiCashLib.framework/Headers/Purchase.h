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

//
//  Purchase.h
//  PsiCashLib
//

#ifndef Purchase_h
#define Purchase_h


@interface PsiCashPurchase : NSObject <NSCoding>
@property (nonnull) NSString* ID;
@property (nonnull) NSString* transactionClass;
@property (nonnull) NSString* distinguisher;
@property (nullable) NSDate* expiry;
@property (nullable) NSString* authorization;

- (id)initWithID:(NSString*_Nonnull)ID
transactionClass:(NSString*_Nonnull)transactionClass
   distinguisher:(NSString*_Nonnull)distinguisher
          expiry:(NSDate*_Nullable)expiry
   authorization:(NSString*_Nullable)authorization;

- (NSDictionary<NSString*,NSObject*>*_Nonnull)toDictionary;
@end


#endif /* Purchase_h */
