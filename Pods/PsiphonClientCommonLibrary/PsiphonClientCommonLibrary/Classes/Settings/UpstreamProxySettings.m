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

#import "UpstreamProxySettings.h"


#pragma mark - ProxySettings class

@interface ProxySettings : NSObject {
}

@property NSString *proxyHost;
@property NSString *proxyPort;

@end

@implementation ProxySettings

- (id)initWithSettings:(NSString*)host port:(NSString*)port {
    self = [super init];
    if (self) {
        self.proxyHost = host;
        self.proxyPort = port;
    }
    return self;
}

@end

#pragma mark - ProxyCredentials class

@interface ProxyCredentials : NSObject {
}

@property NSString *username;
@property NSString *password;
@property NSString *domain;

@end

@implementation ProxyCredentials

- (id)initWithCredentials:(NSString*)username password:(NSString*)password domain:(NSString*)domain {
    self = [super init];
    if (self) {
        self.username = username;
        self.password = password;
        self.domain = domain;
    }
    return self;
}

@end

#pragma mark - ProxyHeaderclass

@interface ProxyHeader : NSObject
@property NSString *name;
@property NSString *value;
@end

@implementation ProxyHeader

- (id)initWithNameAndValue:(NSString*)name value:(NSString*)value {
    self = [super init];
    if (self) {
        self.name = name;
        self.value = value;
    }
    return self;
}

@end

#pragma mark - UpstreamProxySettings class

@implementation UpstreamProxySettings

+ (instancetype)sharedInstance
{
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

+ (NSArray<NSString*>*)defaultSettingsKeys {
    return @[kUpstreamProxyHostAddress, kUpstreamProxyPort, kUseProxyAuthentication];
}

+ (NSArray<NSString*>*)authenticationKeys {
    return @[kProxyUsername, kProxyPassword, kProxyDomain];
}

+ (NSArray<NSString*>*)customHeaderKeys {
    static dispatch_once_t once;
    static NSArray<NSString*> *customHeaderKeys;
    __weak UpstreamProxySettings *safeSelf = [UpstreamProxySettings sharedInstance];
    dispatch_once(&once, ^{
        NSMutableArray *headerKeys = [[NSMutableArray alloc] initWithCapacity:kMaxUpstreamProxyCustomHeaders];

        for (int i = 0; i < kMaxUpstreamProxyCustomHeaders; i++) {
            [headerKeys addObject:[safeSelf getHeaderSeparatorKeyN:i]];
            [headerKeys addObject:[safeSelf getHeaderNameKeyN:i]];
            [headerKeys addObject:[safeSelf getHeaderValueKeyN:i]];
        }
        customHeaderKeys = [NSArray arrayWithArray:headerKeys];
    });
    return customHeaderKeys;
}

- (BOOL)getUseCustomProxySettings {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kUseUpstreamProxy];
}

- (NSString*)getCustomProxyHost {
    NSString *hostAddress = [[NSUserDefaults standardUserDefaults] stringForKey:kUpstreamProxyHostAddress];
    return hostAddress.length == 0 ? @"" : hostAddress;
}

- (NSString*)getCustomProxyPort {
    NSString *proxyPort = [[NSUserDefaults standardUserDefaults] stringForKey:kUpstreamProxyPort];
    return proxyPort.length == 0 ? @"" : proxyPort;
}

- (BOOL)getUseProxyAuthentication {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kUseProxyAuthentication];
}

- (NSString*)getProxyUsername {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kProxyUsername];
}

- (NSString*)getProxyPassword {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kProxyPassword];
}

- (NSString*)getProxyDomain {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kProxyDomain];
}

- (ProxySettings*)getProxySettings {
    if (![self getUseCustomProxySettings]) {
        return nil;
    }

    NSString *proxyHost = [self getCustomProxyHost];
    NSString *proxyPort = [self getCustomProxyPort];

    if (proxyHost.length == 0) {
        return nil;
    }
    if (proxyPort.length == 0) {
        return nil;
    }

    ProxySettings *proxySettings = [[ProxySettings alloc] initWithSettings:proxyHost port:proxyPort];

    return proxySettings;
}

- (ProxyCredentials*)getProxyCredentials {
    if (![self getUseProxyAuthentication]) {
        return nil;
    }

    NSString *username = [self getProxyUsername];
    NSString *password = [self getProxyPassword];
    NSString *domain = [self getProxyDomain];

    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];

    if (username.length == 0 || [username stringByTrimmingCharactersInSet:whitespace].length == 0) {
        return nil;
    }
    if (password.length == 0 || [password stringByTrimmingCharactersInSet:whitespace].length == 0) {
        return nil;
    }
    if (domain.length == 0 || [domain stringByTrimmingCharactersInSet:whitespace].length == 0) {
        return [[ProxyCredentials alloc] initWithCredentials:username password:password domain:@""];
    }

    return [[ProxyCredentials alloc] initWithCredentials:username password:password domain:domain];
}

// Returns a tunnel-core compatible proxy URL for the
// current user configured proxy settings.
// e.g., http://NTDOMAIN%5CNTUser:password@proxyhost:3375,
//       http://user:password@proxyhost:8080,
//       http://user%20name:pass%20word@proxyhost:12345, etc.
- (NSString*)getUpstreamProxyUrl {
    ProxySettings *proxySettings = [self getProxySettings];

    if (proxySettings == nil) {
        return @"";
    }

    NSMutableString *url = [[NSMutableString alloc] initWithString:@"http://"];

    ProxyCredentials *credentials = [self getProxyCredentials];

    if (credentials != nil) {
        if ([credentials.domain length] != 0) {
            NSString *unreserved = @"-._~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
            NSString *subdelims = @"!$&'(/)*+,;=";
            NSString *domainAllowed = [unreserved stringByAppendingString:subdelims];
            NSCharacterSet *domainAllowedCharSet =
                [NSCharacterSet characterSetWithCharactersInString:domainAllowed];
            NSString *encodedDomain =
                [credentials.domain stringByAddingPercentEncodingWithAllowedCharacters:domainAllowedCharSet];
            [url appendString:encodedDomain];
            [url appendString:@"%5C"]; // URL encoding of "\"
        }
        NSString *encodedUsername =
            [credentials.username stringByAddingPercentEncodingWithAllowedCharacters:
             NSCharacterSet.URLUserAllowedCharacterSet];
        [url appendString:encodedUsername];
        [url appendString:@":"];
        NSString *encodedPassword =
            [credentials.password stringByAddingPercentEncodingWithAllowedCharacters:
             NSCharacterSet.URLPasswordAllowedCharacterSet];
        [url appendString:encodedPassword];
        [url appendString:@"@"];
    }

    [url appendString:proxySettings.proxyHost];
    [url appendString:@":"];
    [url appendString:proxySettings.proxyPort];

    return url;
}

- (BOOL)getUseCustomHeaders {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kUseUpstreamProxyCustomHeaders];
}

- (NSString*)getHeaderSeparatorKeyN:(int)n {
    NSString *key = [kUpstreamProxyCustomHeader stringByAppendingString:[NSString stringWithFormat:@"%i", n, nil]];
    return key;
}

- (NSString*)getHeaderNameKeyN:(int)n {
    NSString *key = [kUpstreamProxyCustomHeaderName stringByAppendingString:[NSString stringWithFormat:@"%i", n, nil]];
    return key;
}

- (NSString*)getHeaderValueKeyN:(int)n {
    NSString *key = [kUpstreamProxyCustomHeaderValue stringByAppendingString:[NSString stringWithFormat:@"%i", n, nil]];
    return key;
}

- (ProxyHeader*)getHeaderN:(int)n {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *name = [userDefaults stringForKey:[self getHeaderNameKeyN:n]];
    NSString *value = [userDefaults stringForKey:[self getHeaderValueKeyN:n]];
    if (![name length]) {
        return nil;
    } else if (value == nil) {
        value = @"";
    }

    return [[ProxyHeader alloc] initWithNameAndValue:name value:value];
}

- (NSArray<ProxyHeader*>*)getHeaders {
    if (![self getUseCustomHeaders]) {
        return nil;
    }

    NSMutableArray *headers = [[NSMutableArray alloc] initWithCapacity:kMaxUpstreamProxyCustomHeaders];
    for (int i = 0; i < kMaxUpstreamProxyCustomHeaders; i++) {
        ProxyHeader *header = [self getHeaderN:i];
        if (header) {
            [headers addObject:header];
        }
    }

    return [NSArray arrayWithArray:headers];
}

- (NSDictionary*)getUpstreamProxyCustomHeaders {
    NSArray<ProxyHeader*> *headers = [self getHeaders];

    if (headers == nil) {
        return @{};
    }

    NSMutableDictionary<NSString*, NSArray<NSString*>*> *headersFormattedForJson = [[NSMutableDictionary alloc] initWithCapacity:kMaxUpstreamProxyCustomHeaders];

    for (ProxyHeader *header in headers) {
        [headersFormattedForJson setObject:@[header.value] forKey:header.name];
    }

    return [NSDictionary dictionaryWithDictionary:headersFormattedForJson];
}

@end
