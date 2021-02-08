/*
 * Copyright (c) 2021, Psiphon Inc.
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

import Foundation

/// Represents the current and supported platforms.
public struct Platform {

    public enum SupportedPlatform: Equatable {
        case iOS
        case iOSAppOnMac
    }

    public let current: SupportedPlatform

    public init(_ processInfo: ProcessInfo) {
        if #available(iOS 14.0, *) {
            if processInfo.isiOSAppOnMac {
                self.current = .iOSAppOnMac
            } else {
                self.current = .iOS
            }
        } else {
            self.current = .iOS
        }
    }

}
