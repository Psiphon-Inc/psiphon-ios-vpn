//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

// Adopted from https://github.com/signalapp/SignalServiceKit/blob/master/src/Util/Asserts.h

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
#import "PsiFeedbackLogger.h"

#ifndef PSIAssert

#if DEBUG

// PSIAssert() should be used in Obj-C methods.
// PSICAssert() should be used in free functions.

#define CONVERT_EXPR_TO_STRING(X) #X

#define PSIAssert(X)                                                                                                   \
    if (!(X)) {                                                                                                        \
        [PsiFeedbackLogger error:@"%s Assertion failed: %s", __PRETTY_FUNCTION__, CONVERT_EXPR_TO_STRING(X)];                         \
        NSAssert(0, @"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                               \
    }

#define PSICAssert(X)                                                                                                  \
    if (!(X)) {                                                                                                        \
        [PsiFeedbackLogger error:@"%s Assertion failed: %s", __PRETTY_FUNCTION__, CONVERT_EXPR_TO_STRING(X)];                         \
        NSCAssert(0, @"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                              \
    }

#else

#define PSIAssert(X)
#define PSICAssert(X)

#endif

#endif
