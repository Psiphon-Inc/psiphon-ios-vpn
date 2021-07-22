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

#import "Authorization.h"

@interface Authorization ()

// Base64 authorization value.
@property (nonatomic, readwrite) NSString *rawValue;
@property (nonatomic, readwrite) NSString *ID;
@property (nonatomic, readwrite) NSString *accessType;
@property (nonatomic, readwrite) NSDate *expires;

@end

@implementation Authorization

+ (Authorization *_Nullable)makeFromSharedAuthorization:(SharedAuthorization *_Nullable)sharedAuth {
    
    if (sharedAuth == nil) {
        return nil;
    }
    
    Authorization *instance = [[Authorization alloc] init];
    instance.rawValue = sharedAuth.rawValue;
    instance.ID = sharedAuth.id;
    instance.accessType = sharedAuth.accessType;
    instance.expires = sharedAuth.expires;
    
    return instance;
    
}

- (AuthorizationAccessType)accessTypeValue {
    return [SharedAuthorization accessTypeForString: self.accessType];
}

- (BOOL)isEqual:(id)object {
    // Checks for trivial equality.
    if (self == object) {
        return TRUE;
    }

    // Ignores objects that are not of type Authorization.
    if (![(NSObject *)object isKindOfClass:[Authorization class]]) {
        return FALSE;
    }

    // Authorization IDs are guaranteed to be unique.
    return [self.ID isEqualToString:((Authorization *)object).ID];
}

- (NSUInteger)hash {
    // Authorization ID is itself unique.
    return [self.ID hash];
}

@end
