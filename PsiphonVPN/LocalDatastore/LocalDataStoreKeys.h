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

#import <Foundation/Foundation.h>
#import "KeyedDataStore.h"

/**
* LocalDataStoreKeys
*
* Keys to access the local datastore.
*
* Each key must be unique and ideally composed in this way:
* [Full name of associated class] . [UniquePartOfName] + [Type] + Key
*
* e.g. In SettingsViewController you might have:
* UserDefaultsKey const SettingsConnectOnDemandBoolKey = @"SettingsViewController.ConnectOnDemandBoolKey"
*
*/

/// Key for the ID of the last authorization obtained from the verifier server. Type: NSString.
FOUNDATION_EXTERN KeyedDataStoreKey const LastAuthIDKey;

/// Key for the access type of the last authorization obtained from the verifier server. Type: NSString.
FOUNDATION_EXTERN KeyedDataStoreKey const LastAuthAccessTypeKey;

/// Key for the time when the extension was last started. Type: NSDate.
FOUNDATION_EXTERN KeyedDataStoreKey const ExtensionStartTimeKey;

/// Key for the time when the ticker last fired in the extension. Type: NSDate.
FOUNDATION_EXTERN KeyedDataStoreKey const TickerTimeKey;
