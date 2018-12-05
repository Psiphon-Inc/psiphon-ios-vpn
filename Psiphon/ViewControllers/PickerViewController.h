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


NS_ASSUME_NONNULL_BEGIN

@interface PickerViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

/**
 * Index of item that is currently selected. Default value is 0.
 */
@property (nonatomic) NSUInteger selectedIndex;

@property (nonatomic, copy, nullable) void (^selectionHandler)(NSUInteger selectedIndex,
                                                              PickerViewController *viewController);

- (instancetype)initWithLabels:(NSArray<NSString *> *)pickerLabels
                     andImages:(NSArray<UIImage *> *_Nullable)pickerImages;

@end

NS_ASSUME_NONNULL_END
