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

#import <UIKit/UIKit.h>
#import "AutoLayoutProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SkyButton : UIControl <AutoLayoutProtocol>

@property (nonatomic, readonly) UILabel *titleLabel;

@property (nonatomic, readonly, nullable) NSString *currentTitle;

/**
 * Default value is FALSE.
 */
@property (nonatomic, assign) BOOL shadow;

@property (nonatomic, assign) CGFloat fontSize;

- (instancetype)initForAutoLayout;

- (void)autoLayoutInit;

- (void)setTitle:(NSString *)title;

- (void)setTitle:(NSString *)title forState:(UIControlState)controlState;

/**
 * Subclasses can override this method to customize the title style.
 */
- (NSAttributedString *_Nullable)styleTitleText:(NSString *)title;

/**
 * Updates title to reflect current view state.
 *
 * Subclasses should override `-currentTitle` and call this method to update title.
 */
- (void)updateTitle;

@end

NS_ASSUME_NONNULL_END
