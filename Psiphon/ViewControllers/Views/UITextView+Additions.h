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
#import <UIKit/UIKit.h>

extern NSErrorDomain const LinkGenerationErrorDomain;

typedef NS_ERROR_ENUM(LinkGenerationErrorDomain, LinkGenerationErrorCode) {
    LinkGenerationFailedToFindHref = 3001,
    LinkGenerationFailedToGenerateURL = 3002,
    LinkGenerationFailedToFindCloseTag = 3003,
};

NS_ASSUME_NONNULL_BEGIN

@interface UITextView (Additions)

/**
 * Looks in target text view's text for html links of the form
 * <a href="http://psiphon3.com">some text</a>.
 * If found these tags are removed and an attributed string is formed with these links.
 * The text view is then set to use this attributed string.
 *
 * @return nil if no error occurred, return an error with domain
 * `LinkGenerationErrorDomain` otherwise.
 */
- (NSError *_Nullable)replaceLinksInText;

@end

NS_ASSUME_NONNULL_END
