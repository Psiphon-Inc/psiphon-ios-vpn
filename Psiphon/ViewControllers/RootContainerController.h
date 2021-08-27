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

#import <UIKit/UIKit.h>

@interface RootContainerController : UIViewController

/**
 * Dismisses `MainViewController` and all modally presented view controllers,
 * then adds a new instance of `MainViewController` as a child view controller to self.
 */
- (void)reloadMainViewControllerAnimated:(BOOL)animated
                              completion:(void (^ __nullable)(void))completion;
/**
 * Destroys current Onboarding view controller and create a new one.
 */
- (void)reloadOnboardingViewController;

@end
