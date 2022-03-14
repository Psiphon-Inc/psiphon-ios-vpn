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

import Foundation
import ReactiveSwift

/// A property manager that reads and writes values on the main-thread,
/// and provides utilities to observe changes in value.
@propertyWrapper
public final class MainState<Value> {
    private let passthroughSubject = Signal<Value, Never>.pipe()

    private var value: Value {
        didSet {
            self.passthroughSubject.input.send(value: wrappedValue)
        }
    }

    public var wrappedValue: Value {
        get {
            precondition(Thread.isMainThread)
            return value
        }
        set {
            precondition(Thread.isMainThread)
            value = newValue
        }
    }

    public var projectedValue: MainState<Value> { self }

    public var signal: Signal<Value, Never> {
        return passthroughSubject.output
    }

    public var signalProducer: SignalProducer<Value, Never> {
        SignalProducer { [unowned self] observer, lifetime in
            if Thread.isMainThread {
                observer.send(value: self.wrappedValue)
                lifetime += self.passthroughSubject.output.observe(observer)
            } else {
                DispatchQueue.main.async {
                    observer.send(value: self.wrappedValue)
                    lifetime += self.passthroughSubject.output.observe(observer)
                }
            }
        }
    }

    public init(wrappedValue: Value) {
        precondition(Thread.isMainThread)
        self.value = wrappedValue
    }

    deinit {
        self.passthroughSubject.input.sendCompleted()
    }
}
