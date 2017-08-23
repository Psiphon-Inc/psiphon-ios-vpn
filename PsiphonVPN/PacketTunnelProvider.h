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

#import <NetworkExtension/NEPacketTunnelProvider.h>

// PsiphonTunnel Errors
#define PSIPHON_TUNNEL_ERROR_DOMAIN             @"psiphonTunnelErrorSettingsDomain"
#define PSIPHON_TUNNEL_ERROR_BAD_CONFIGURATION  1
#define PSIPHON_TUNNEL_ERROR_INTERAL_ERROR      2
#define PSIPHON_TUNNEL_ERROR_BAD_START          3  // Error code for when the user tries to start the VPN anywhere butthe container app.
#define PSIPHON_TUNNEL_ERROR_STOPPED_BEFORE_CONNECTED 4

@interface PacketTunnelProvider : NEPacketTunnelProvider

@end
