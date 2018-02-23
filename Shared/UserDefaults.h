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

/**
 * NSUserDefaults key type.
 *
 * UserDefaultsKey identifier should be composed in this way:
 * [Name of associated class (or first part of name for long class names] + [UniquePartOfName] + [Type] + Key
 *
 * NSUserDefaults key string should be composed in this way:
 * [Full name of associated class] . [UniquePartOfName] + [Type] + Key
 *
 * e.g. In SettingsViewController you might have:
 * UserDefaultsKey const SettingsConnectOnDemandBoolKey = @"SettingsViewController.ConnectOnDemandBoolKey"
 *
 */
typedef NSString * UserDefaultsKey;


/**
 * Protocol for model objects that store their data using NSUserDefaults.
 */
@protocol UserDefaultsModelProtocol

@required

+ (id _Nonnull)fromPersistedDefaults;

- (BOOL)isEmpty;

- (BOOL)persistChanges;

@end
