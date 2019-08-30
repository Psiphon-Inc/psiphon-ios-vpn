/*
* Copyright (c) 2019, Psiphon Inc.
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
#import "SkyButton.h"

NS_ASSUME_NONNULL_BEGIN

@interface BorderedSubtitleButton : SkyButton

@property (nonatomic, readonly) UILabel *subtitleLabel;

/**
 Hides subtitleLabel from the view, this is non-reversible.
 */
- (void)removeSubtitleLabel;

@end

NS_ASSUME_NONNULL_END
