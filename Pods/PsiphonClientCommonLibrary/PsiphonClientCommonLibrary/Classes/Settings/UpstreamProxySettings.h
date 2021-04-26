/*
 * Copyright (c) 2016, Psiphon Inc.
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

#define kUseUpstreamProxy                @"useUpstreamProxy"
#define kUseProxyAuthentication          @"useProxyAuthentication"
#define kProxyUsername                   @"proxyUsername"
#define kProxyPassword                   @"proxyPassword"
#define kProxyDomain                     @"proxyDomain"
#define kUpstreamProxyHostAddress        @"upstreamProxyHostAddress"
#define kUpstreamProxyPort               @"upstreamProxyPort"
#define kUpstreamProxyPort               @"upstreamProxyPort"
#define kUseUpstreamProxyCustomHeaders   @"useUpstreamProxyCustomHeaders"
#define kSetUpstreamProxyCustomHeaders   @"setUpstreamProxyCustomHeaders"
#define kUpstreamProxyCustomHeader       @"upstreamProxyCustomHeader"
#define kUpstreamProxyCustomHeaderName   @"upstreamProxyCustomHeaderName"
#define kUpstreamProxyCustomHeaderValue  @"upstreamProxyCustomHeaderValue"
#define kMaxUpstreamProxyCustomHeaders   6

@interface UpstreamProxySettings : NSObject
+ (instancetype)sharedInstance;
+ (NSArray<NSString*>*)defaultSettingsKeys;
+ (NSArray<NSString*>*)authenticationKeys;
+ (NSArray<NSString*>*)customHeaderKeys;

- (NSString*)getUpstreamProxyUrl;
- (BOOL)getUseCustomProxySettings;
- (NSString*)getCustomProxyHost;
- (NSString*)getCustomProxyPort;
- (BOOL)getUseProxyAuthentication;
- (NSString*)getProxyUsername;
- (NSString*)getProxyPassword;
- (NSString*)getProxyDomain;
- (BOOL)getUseCustomHeaders;
- (NSString*)getHeaderNameKeyN:(int)n;
- (NSString*)getHeaderValueKeyN:(int)n;
- (NSDictionary*)getUpstreamProxyCustomHeaders;
@end
