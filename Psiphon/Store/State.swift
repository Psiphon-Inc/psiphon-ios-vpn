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

@propertyWrapper
public final class State<Value> {
    private let passthroughSubject = Signal<Value, Never>.pipe()

    public var wrappedValue: Value {
        didSet {
            self.passthroughSubject.input.send(value: wrappedValue)
        }
    }

    public var projectedValue: State<Value> { self }

    public var signal: Signal<Value, Never> {
        return passthroughSubject.output
    }

    public var signalProducer: SignalProducer<Value, Never> {
        return SignalProducer { [unowned self] observer, lifetime in
            observer.send(value: self.wrappedValue)
            lifetime += self.passthroughSubject.output.observe(observer)
        }
    }

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    deinit {
        self.passthroughSubject.input.sendCompleted()
    }
}
