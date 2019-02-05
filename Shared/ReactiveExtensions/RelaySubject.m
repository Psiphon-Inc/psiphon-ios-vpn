/*
 * Copyright (c) 2019, Psiphon Inc.
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

#import "RelaySubject.h"


@implementation RelaySubject

- (void)accept:(id)value {
    [super sendNext:value];
}

- (void)sendNext:(id)value {
    @throw [NSException exceptionWithName:@"InvalidMethodCalled"
                                   reason:@"sendNext not allowed on relay. Use -accept:"
                                 userInfo:nil];
}

- (void)sendError:(nullable NSError *)error {
    @throw [NSException exceptionWithName:@"InvalidMethodCalled"
                                   reason:@"Can't send error on relay subject."
                                 userInfo:nil];
}

- (void)sendCompleted {
    @throw [NSException exceptionWithName:@"InvalidMethodCalled"
                                   reason:@"Can't send completed on relay subject."
                                 userInfo:nil];
}

@end

@implementation BehaviorRelay

- (void)accept:(id)value {
    [super sendNext:value];
}

- (void)sendNext:(id)value {
    @throw [NSException exceptionWithName:@"InvalidMethodCalled"
                                   reason:@"sendNext not allowed on relay. Use -accept:"
                                 userInfo:nil];
}

- (void)sendError:(nullable NSError *)error {
    @throw [NSException exceptionWithName:@"InvalidMethodCalled"
                                   reason:@"Can't send error on relay subject."
                                 userInfo:nil];
}

- (void)sendCompleted {
    @throw [NSException exceptionWithName:@"InvalidMethodCalled"
                                   reason:@"Can't send completed on relay subject."
                                 userInfo:nil];
}

@end
