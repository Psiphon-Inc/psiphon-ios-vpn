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

/**
 * Bridge header file between the extension and the container.
 */

// Network Extension options
#define EXTENSION_OPTION_START_FROM_CONTAINER @"startFromContainer"
#define EXTENSION_OPTION_TRUE @"true"

// Network Extension queries
#define EXTENSION_QUERY_IS_PROVIDER_ZOMBIE @"isProviderZombie"
#define EXTENSION_QUERY_IS_TUNNEL_CONNECTED @"isTunnelConnected"

// Network Extension boolean query responses
#define EXTENSION_RESP_TRUE @"true"
#define EXTENSION_RESP_FALSE @"false"

// Notifier keys
// Prefix determines the source of the notification.
// Notifications that start with "NE." are sent from the network extension.
#define NOTIFIER_START_VPN @"VPNManager.startVPN"
#define NOTIFIER_FORCE_SUBSCRIPTION_CHECK @"VPNManager.forceSubscriptionCheck"
#define NOTIFIER_APP_DID_ENTER_BACKGROUND @"AppDelegate.applicationDidEnterBackground"

#define NOTIFIER_NEW_HOMEPAGES @"NE.newHomepages"
#define NOTIFIER_TUNNEL_CONNECTED @"NE.tunnelConnected"
#define NOTIFIER_ON_AVAILABLE_EGRESS_REGIONS @"NE.onAvailableEgressRegions"