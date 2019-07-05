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

import UIKit

@objc class EventHandler: NSObject {

    private let handler: () -> Void

    init(_ handler:@escaping () -> Void) {
        self.handler = handler
    }

    @objc func handleEvent() {
        handler()
    }

}

class SwiftUIButton: UIButton {

    private var eventHandler: EventHandler!

    /// Sets `handler` closure as the event handler for this instance.
    /// - Note: Current implementation resets previously set handlers.
    func setEventHandler(for event: UIControl.Event = .touchUpInside,
                         _ handler: @escaping () -> Void) {
        self.eventHandler = EventHandler(handler)
        addTarget(self.eventHandler, action: #selector(EventHandler.handleEvent), for: event)
    }

}


