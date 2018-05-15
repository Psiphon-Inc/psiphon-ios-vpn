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

#import "Pastel.h"

CGPoint PastelPoint(PastelDirection dir) {
    switch (dir) {
        case left:
            return CGPointMake(0.0, 0.5);
        case top:
            return CGPointMake(0.5, 0.0);
        case right:
            return CGPointMake(1.0, 0.5);
        case bottom:
            return CGPointMake(0.5, 1.0);
        case topLeft:
            return CGPointMake(0.0, 0.0);
        case topRight:
            return CGPointMake(1.0, 0.0);
        case bottomLeft:
            return CGPointMake(0.0, 1.0);
        case bottomRight:
            return CGPointMake(1.0, 1.0);
    }
}
