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

/**
 * This class provides convenience methods for profiling app performance.
 */
@interface AppStats : NSObject


/**
 * Gets size of each memory page in bytes.
 * @return Memory page size.
 */
+ (vm_size_t)pageSize:(NSError **)error;

/**
 * Returns current mach tasks's resident set size.
 *
 * @param e A pointer to an error object. If an error occures, it will be set to
 * an error object describing the error. Otherwise, set to nil.
 *
 * @return Resident set size.
 */
+ (mach_vm_size_t)residentSetSize:(NSError *_Nullable*_Nonnull)e;

/**
 * Returns current mach task's private resident set size.
 *
 * @param e A pointer to an error object. If an error occures, it will be set to
 * an error object describing the error. Otherwise, set to nil.
 *
 * @return Private resident set size.
 */
+ (size_t)privateResidentSetSize:(NSError *_Nullable*_Nonnull)e;

@end
