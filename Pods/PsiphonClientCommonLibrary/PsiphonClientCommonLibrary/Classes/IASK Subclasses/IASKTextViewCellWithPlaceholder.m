/*
 * Copyright (c) 2020, Psiphon Inc.
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

#import "IASKTextViewCellWithPlaceholder.h"

@interface IASKTextViewCellWithPlaceholder ()

@property (nonatomic, assign) BOOL showingPlaceholder;

@end

@implementation IASKTextViewCellWithPlaceholder {
    NSString *placeholder;
}

- (instancetype)initWithPlaceholder:(NSString*)placeholder {
    self = [super init];
    if (self) {
        self->placeholder = placeholder;
        self.textView.delegate = self;
        [self showPlaceholder];
    }
    return self;
}

#pragma mark - UITextView delegate methods

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView
{
    if (self.showingPlaceholder == TRUE) {
        self.textView.text = @"";
        if (@available(iOS 13.0, *)) {
            self.textView.textColor = UIColor.labelColor;
        } else {
            // Fallback on earlier versions
            self.textView.textColor = UIColor.blackColor;
        }
        self.showingPlaceholder = FALSE;
    }

    return YES;
}

- (void)textViewDidChange:(UITextView *)textView
{
    [self showPlaceholderIfInputEmpty];
}

- (BOOL)textViewShouldEndEditing:(UITextView *)textView
{
    [self showPlaceholderIfInputEmpty];
    return YES;
}

#pragma mark - Helpers

- (void)showPlaceholderIfInputEmpty {
    if (self.showingPlaceholder == FALSE) {
        if (self.textView.text.length == 0) {
            [self showPlaceholder];
            [self.textView resignFirstResponder];
        }
    }
}

- (void)showPlaceholder {
    self.textView.text = self->placeholder;
    self.showingPlaceholder = TRUE;
    if (@available(iOS 13.0, *)) {
        self.textView.textColor = UIColor.tertiaryLabelColor;
    } else {
        // Fallback on earlier versions
        self.textView.textColor = UIColor.lightGrayColor;
    }
}

@end
