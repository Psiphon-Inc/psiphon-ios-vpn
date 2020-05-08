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
#define EXTENSION_QUERY_TUNNEL_PROVIDER_STATE @"queryTunnelProviderState"

// Integer codes for `TunnelStartStopIntent`.
#define TUNNEL_INTENT_UNDEFINED 0
#define TUNNEL_INTENT_START 1
#define TUNNEL_INTENT_STOP 2
