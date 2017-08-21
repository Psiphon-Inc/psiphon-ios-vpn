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

#import <PsiphonTunnel/PsiphonTunnel.h>
#import <NetworkExtension/NEPacketTunnelNetworkSettings.h>
#import <NetworkExtension/NEIPv4Settings.h>
#import <NetworkExtension/NEDNSSettings.h>
#import <NetworkExtension/NEPacketTunnelFlow.h>
#import "PacketTunnelProvider.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"

static const double kDefaultLogTruncationInterval = 12 * 60 * 60; // 12 hours

@implementation PacketTunnelProvider {
    PsiphonTunnel *psiphonTunnel;
    PsiphonDataSharedDB *sharedDB;

    // Notifier
    Notifier *notifier;

    // Tracking state of the extension
    NSMutableArray<NSString *> *handshakeHomepages;
    BOOL firstOnConnected;
}

- (id)init {
    self = [super init];

    if (self) {
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        // Notifier
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        //
        handshakeHomepages = [[NSMutableArray alloc] init];
        firstOnConnected = TRUE;
    }
    
    return self;
}

- (void)startTunnelWithOptions:(nullable NSDictionary<NSString *, NSObject *> *)options completionHandler:(void (^)(NSError *__nullable error))completionHandler {

    // TODO: This method wouldn't work with "boot to VPN"
    if (options[EXTENSION_OPTION_START_FROM_CONTAINER]) {

        // Truncate logs every 12 hours
        [sharedDB truncateLogsOnInterval:(NSTimeInterval) kDefaultLogTruncationInterval];

        // Create our tunnel instance
        psiphonTunnel = [PsiphonTunnel newPsiphonTunnel:(id <TunneledAppDelegate>) self];
        __weak PsiphonTunnel *weakPsiphonTunnel = psiphonTunnel;

        [self setTunnelNetworkSettings:[self getTunnelSettings] completionHandler:^(NSError *_Nullable error) {

            if (error != nil) {
                NSLog(@"setTunnelNetworkSettings failed: %@", error);
                completionHandler([[NSError alloc] initWithDomain:PSIPHON_TUNNEL_ERROR_DOMAIN code:PSIPHON_TUNNEL_ERROR_BAD_CONFIGURATION userInfo:nil]);
                return;
            }

            // TODO: don't start VPN until Psiphon is connected?

            BOOL success = [weakPsiphonTunnel start:FALSE];
            if (!success) {
                NSLog(@"psiphonTunnel.start failed");
                completionHandler([[NSError alloc] initWithDomain:PSIPHON_TUNNEL_ERROR_DOMAIN code:PSIPHON_TUNNEL_ERROR_INTERAL_ERROR userInfo:nil]);
                return;
            }

            completionHandler(nil);
        }];
    } else {
        // TODO: localize the following string
        [self displayMessage:
            NSLocalizedString(@"To connect, use the Psiphon application.", @"Alert message informing user they have to open the app")
          completionHandler:^(BOOL success) {
//               TODO: error handling?
          }];

        completionHandler([NSError
          errorWithDomain:PSIPHON_TUNNEL_ERROR_DOMAIN code:PSIPHON_TUNNEL_ERROR_BAD_START userInfo:nil]);
    }
    
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void)) completionHandler {
    
    // TODO: assumes stopTunnelWithReason called exactly once only after startTunnelWithOptions.completionHandler(nil)

    [psiphonTunnel stop];
    completionHandler();
    
    return;
}

- (void)handleAppMessage:(NSData *)messageData completionHandler:(nullable void (^)(NSData * __nullable responseData))completionHandler {
    
    if (completionHandler != nil) {
        completionHandler(messageData);
    }
}


- (void)sleepWithCompletionHandler:(void (^)(void))completionHandler {
    completionHandler();
}

- (void)wake {
}

- (NEPacketTunnelNetworkSettings *)getTunnelSettings {
    
    // TODO: select available private address range, like Android does:
    // https://github.com/Psiphon-Labs/psiphon-tunnel-core/blob/cff370d33e418772d89c3a4a117b87757e1470b2/MobileLibrary/Android/PsiphonTunnel/PsiphonTunnel.java#L718
    
    NEPacketTunnelNetworkSettings *newSettings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:@"172.16.0.1"];
    
    newSettings.IPv4Settings = [[NEIPv4Settings alloc] initWithAddresses:@[@"172.16.0.2"] subnetMasks:@[@"255.255.0.0"]];
    
    newSettings.IPv4Settings.includedRoutes = @[[NEIPv4Route defaultRoute]];
    newSettings.IPv4Settings.excludedRoutes = @[[[NEIPv4Route alloc] initWithDestinationAddress:@"172.16.0.0" subnetMask:@"255.255.0.0"]];
    
    // TODO: call getPacketTunnelDNSResolverIPv6Address
    newSettings.DNSSettings = [[NEDNSSettings alloc] initWithServers:@[[psiphonTunnel getPacketTunnelDNSResolverIPv4Address]]];
    
    newSettings.DNSSettings.searchDomains = @[@""];
    
    newSettings.MTU = [NSNumber numberWithLong: [psiphonTunnel getPacketTunnelMTU]];
    
    return newSettings;
}

@end

#pragma mark - TunneledAppDelegate

@interface PacketTunnelProvider (AppDelegateExtension) <TunneledAppDelegate>
@end

@implementation PacketTunnelProvider (AppDelegateExtension)

- (NSString * _Nullable)getEmbeddedServerEntries {
    return @"";
}

- (NSString * _Nullable)getPsiphonConfig {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *bundledConfigPath = [[[NSBundle mainBundle] resourcePath]
      stringByAppendingPathComponent:@"psiphon_config"];

    if (![fileManager fileExistsAtPath:bundledConfigPath]) {
        NSLog(@"Config file not found. Aborting now.");
        abort();
    }

    // Read in psiphon_config JSON
    NSData *jsonData = [fileManager contentsAtPath:bundledConfigPath];
    NSError *err = nil;
    NSDictionary *readOnly = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&err];

    NSMutableDictionary *mutableConfigCopy = [readOnly mutableCopy];

    if (err) {
        NSLog(@"Failed to parse config JSON. Aborting now.");
        abort();
    }

    // TODO: apply mutations to config here
    NSNumber *fd = (NSNumber*)[[self packetFlow] valueForKeyPath:@"socket.fileDescriptor"];

    mutableConfigCopy[@"PacketTunnelTunFileDescriptor"] = fd;

    jsonData  = [NSJSONSerialization dataWithJSONObject:mutableConfigCopy
      options:0 error:&err];

    if (err) {
        NSLog(@"Failed to create JSON data from config object. Aborting now.");
        abort();
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)onDiagnosticMessage:(NSString * _Nonnull)message {
    [sharedDB insertDiagnosticMessage:message];
    // notify container that there is new data in shared sqlite database
    [notifier post:@"NE.onDiagnosticMessage"];
}

- (void)onConnecting {
    NSLog(@"onConnecting");

    self.reasserting = TRUE;
    
    // Clear list of handshakeHomepages.
    [handshakeHomepages removeAllObjects];
}

- (void)onConnected {
    NSLog(@"onConnected");

    self.reasserting = FALSE;
    
    // Logic that should run only on the first call to onConnected
    // from the when the user starts the VPN from the container.
    if (firstOnConnected) {
        firstOnConnected = FALSE;

        if ([handshakeHomepages count] > 0) {
            BOOL success = [sharedDB insertNewHomepages:handshakeHomepages];
            if (success) {
                [notifier post:@"NE.newHomepages"];
                [handshakeHomepages removeAllObjects];
            }
        }
    }

    // Notify container
    [notifier post:@"NE.onConnected"];
}

- (void)onHomepage:(NSString * _Nonnull)url {
    for (NSString *p in handshakeHomepages) {
        if ([url isEqualToString:p]) {
            return;
        }
    }
    [handshakeHomepages addObject:url];
}

@end
