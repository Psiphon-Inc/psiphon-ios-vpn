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

#import "PsiCashAuthPackage.h"
#import "PsiCashErrorTypes.h"
#import "PsiFeedbackLogger.h"

@interface PsiCashAuthPackage ()
@property (nonatomic, assign, readwrite) BOOL hasEarnerToken;
@property (nonatomic, assign, readwrite) BOOL hasIndicatorToken;
@property (nonatomic, assign, readwrite) BOOL hasSpenderToken;
@end

@implementation PsiCashAuthPackage

- (id)initWithValidTokens:(NSArray<NSString*>*)validTokenTypes {
    self = [super init];

    if (self) {
        if (validTokenTypes == nil || [validTokenTypes count] == 0) {
            [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s no valid tokens for auth package", __FUNCTION__];
        }

        for (NSString *tokenType in validTokenTypes) {
            // TODO: (1.0) check for duplicates
            if ([tokenType isEqualToString:@"earner"]) {
                self.hasEarnerToken = YES;
            } else if ([tokenType isEqualToString:@"indicator"]) {
                self.hasIndicatorToken = YES;
            } else if ([tokenType isEqualToString:@"spender"]) {
                self.hasSpenderToken = YES;
            } else {
                [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"%s encountered invalid token type %@", __FUNCTION__, tokenType]; // TODO: sanitize token type?
            }
        }
    }

    return self;
}

@end
