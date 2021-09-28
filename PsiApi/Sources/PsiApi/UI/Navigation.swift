/*
 * Copyright (c) 2020, Psiphon Inc.
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

/// Represents screens displayed from a given view controller.
public enum Navigation<PresentedScreen: Hashable>: Hashable {
    
    /// Current view controller is dismissed.
    case parent
    
    /// View controller's main screen is displayed, and there are no presented view controllers.
    case mainScreen
    
    /// Represents the screen that is presented by the given view controller.
    case presented(PresentedScreen)
}

/// Represents navigation state of a view controller.
public typealias NavigationState<PresentedScreen: Hashable> =
    PendingValue<Navigation<PresentedScreen>, Navigation<PresentedScreen>>
