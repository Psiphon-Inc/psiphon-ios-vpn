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

// MARK: UIControl Swift Bridge

@objc final class EventHandler: NSObject {

    private let handler: () -> Void

    init(_ handler:@escaping () -> Void) {
        self.handler = handler
    }

    @objc func handleEvent() {
        handler()
    }

}

@objc class SwiftUIControl: UIControl {
 
    private var eventHandler: EventHandler!
    
    /// Sets `handler` as the event handler for this instance.
    /// - Note: Current implementation resets any previously set handler.
    func setEventHandler(for event: UIControl.Event = .touchUpInside,
                         _ handler: @escaping () -> Void) {
        self.eventHandler = EventHandler(handler)
        addTarget(self.eventHandler, action: #selector(EventHandler.handleEvent), for: event)
    }
    
}

@objc class SwiftUIButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.titleLabel?.adjustsFontSizeToFitWidth = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var eventHandler: EventHandler!

    /// Sets `handler` as the event handler for this instance.
    /// - Note: Current implementation resets any previously set handler.
    func setEventHandler(for event: UIControl.Event = .touchUpInside,
                         _ handler: @escaping () -> Void) {
        self.eventHandler = EventHandler(handler)
        addTarget(self.eventHandler, action: #selector(EventHandler.handleEvent), for: event)
    }

}

// MARK: NSNotification Bridge

typealias NotificationCallback = (Notification.Name, Any?) -> Void

struct NotificationObserver {

    private let observers: [ObjCNotificationObserver]

    init(_ names: [Notification.Name], _ callback: @escaping NotificationCallback) {
        observers = names.map {
            ObjCNotificationObserver.create(name: $0, callback: callback)
        }
    }

}


@objc final class ObjCNotificationObserver: NSObject {

    private let callback: NotificationCallback

    private init(callback: @escaping NotificationCallback) {
        self.callback = callback
    }

    static func create(name: Notification.Name,
                      callback: @escaping NotificationCallback) -> ObjCNotificationObserver {

        let observer = ObjCNotificationObserver(callback: callback)
        NotificationCenter.default.addObserver(observer,
                                               selector: #selector(
                                                ObjCNotificationObserver.notify(notification:)),
                                               name: name,
                                               object: nil)

        return observer
    }

    @objc private func notify(notification: NSNotification) {
        callback(notification.name, notification.object)
    }

}

