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
#import "RegionAdapter.h"
#import "SettingsViewController.h"

@class RACSignal<__covariant ValueType>;
@class RACUnit;

NS_ASSUME_NONNULL_BEGIN

@interface MainViewController : UIViewController <PsiphonSettingsViewControllerDelegate,
                                                  RegionAdapterDelegate>

@property (nonatomic) BOOL openSettingImmediatelyOnViewDidAppear;

- (instancetype)initWithStartingVPN:(BOOL)startVPN;

/**
 * Cold terminating signal that emits RACUnit and then completes when all necessary
 * loading operations before showing the MainViewController UI are finished.
 *
 * This signal should ideally be subscribed to after first initializing the MainViewController.
 */
@property (nonatomic, readonly) RACSignal<RACUnit *> *activeStateLoadingSignal;

@end

NS_ASSUME_NONNULL_END
