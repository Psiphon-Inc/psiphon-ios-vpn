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

#import "UITextView+Additions.h"
#import "NSError+Convenience.h"

NSErrorDomain const LinkGenerationErrorDomain = @"LinkGenerationErrorDomain";

@implementation UITextView (Additions)

- (NSError *_Nullable)replaceLinksInText {
    NSString *openTag = @"<a[^>]+href=\"(.*?)\"[^>]*>";
    NSString *closeTag = @"</a>";

    NSError *err;
    NSRegularExpression *openTagRegex = [NSRegularExpression regularExpressionWithPattern:openTag
                                                                                  options:0
                                                                                    error:&err];
    if (*err != nil) {
        return err;
    }

    NSRegularExpression *closeTagRegex = [NSRegularExpression regularExpressionWithPattern:closeTag
                                                                                   options:0
                                                                                     error:&err];
    if (*err != nil) {
        return err;
    }

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:@""];

    NSString *text = self.text;

    while (text.length > 0) {
        // Remove open tag
        NSArray<NSTextCheckingResult*> *openTagMatches = [openTagRegex matchesInString:text
          options:0 range:NSMakeRange(0, text.length)];

        if (openTagMatches == nil || openTagMatches.count == 0) {
            break;
        }

        NSTextCheckingResult *openTagMatch = openTagMatches[0];
        NSString *openTagText = [text
          substringWithRange:NSMakeRange(openTagMatch.range.location, openTagMatch.range.length)];
        text = [text stringByReplacingCharactersInRange:openTagMatch.range
                                                       withString:@""];

        // Get link
        NSDataDetector *detect = [[NSDataDetector alloc] initWithTypes:NSTextCheckingTypeLink
          error:&err];
        if (*err != nil) {
            return err;
        }

        NSArray<NSTextCheckingResult*> *hrefMatches = [detect matchesInString:openTagText
                                                        options:0
                                                          range:NSMakeRange(0, openTagText.length)];

        if (hrefMatches == nil || hrefMatches.count == 0) {
            return [NSError errorWithDomain:LinkGenerationErrorDomain
                                       code:LinkGenerationFailedToFindHref];
        }

        NSTextCheckingResult *hrefMatch = hrefMatches[0];
        NSString *hrefText = [openTagText
          substringWithRange:NSMakeRange(hrefMatch.range.location, hrefMatch.range.length)];
        NSURL *url = [NSURL URLWithString:hrefText];
        if (url == nil) {
            return [NSError errorWithDomain:LinkGenerationErrorDomain
                                       code:LinkGenerationFailedToGenerateURL];
        }

        // Remove close tag
        NSArray<NSTextCheckingResult*> *closeTagMatches = [closeTagRegex
          matchesInString:text
                  options:0
                    range:NSMakeRange(0, text.length)];
        if (closeTagMatches == nil || closeTagMatches.count == 0) {
            return [NSError errorWithDomain:LinkGenerationErrorDomain
                                       code:LinkGenerationFailedToFindCloseTag];
        }

        NSTextCheckingResult *closeTagMatch = closeTagMatches[0];
        text =  [text stringByReplacingCharactersInRange:closeTagMatch.range withString:@""];

        // Remove remaining text for next processing round
        NSString *chunkText = [text
          substringWithRange:NSMakeRange(0, closeTagMatch.range.location)];

        text = [text
          substringWithRange:NSMakeRange(closeTagMatch.range.location,
                                         text.length - closeTagMatch.range.location)];

        // Create link
        NSRange linkRange = NSMakeRange(openTagMatch.range.location,
                                        chunkText.length - openTagMatch.range.location);
        NSDictionary *linkAttributes = @{NSLinkAttributeName: url, NSFontAttributeName: self.font};

        NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc]
          initWithString:chunkText
              attributes:@{NSFontAttributeName: self.font}];

        [attributedString setAttributes:linkAttributes range:linkRange];
        [attr appendAttributedString:attributedString];
    }

    if (attr.string.length > 0) {
        if (text.length != 0) {
            // Add remaining unprocessed text
            [attr appendAttributedString:[[NSAttributedString alloc] initWithString:text
                                                      attributes:@{NSFontAttributeName:self.font}]];
        }
        self.attributedText = attr;
    }

    return nil;
}

@end
