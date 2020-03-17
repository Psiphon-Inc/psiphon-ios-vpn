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

import Foundation
import ReactiveSwift
import Promises

struct TimeoutError: Error {}

extension Signal {

    func observeOnUIScheduler() -> Signal<Value, Error> {
        return self.observe(on: UIScheduler())
    }

}

extension SignalProducer {

    func observeOnUIScheduler() -> SignalProducer<Value, Error> {
        return self.observe(on: UIScheduler())
    }

}

extension SignalProducer where Error == Never {

    // TODO: Check the promise lifecycle.
    static func mapAsync(promise: Promise<Value>) -> SignalProducer<Value, Error> {
        return SignalProducer.init { observer, lifetime in
            promise.then { result in
                observer.send(value: result)
                observer.sendCompleted()
            }.catch { error in
                fatalError("promise should fail by emitting a result ('\(error)')")
            }
        }
    }
    
}

extension Signal where Error == Never {

    func observe<A>(store: Store<A, Value>) -> Disposable? {
        return self.observeValues { [unowned store] (value: Signal.Value) in
            store.send(value)
        }
    }

}

extension Signal where Value == Bool, Error == Never {

    func falseIfNotTrue(within timeout: DispatchTimeInterval) -> Signal<Bool, Never> {
        precondition(timeout != .never)

        return self.filter { $0 == true }
            .take(first: 1)
            .timeout(after: timeout.toDouble()!, raising: TimeoutError(), on: QueueScheduler())
            .flatMapError { anyError -> SignalProducer<Bool, Error> in
                return .init(value: false)
            }
    }

}

extension SignalProducer where Value == Bool, Error == Never {

    func falseIfNotTrue(within timeout: DispatchTimeInterval) -> SignalProducer<Bool, Never> {
        precondition(timeout != .never)

        return self.producer.filter { $0 == true }
            .take(first: 1)
            .timeout(after: timeout.toDouble()!, raising: TimeoutError(), on: QueueScheduler())
            .flatMapError { anyError -> SignalProducer<Bool, Error> in
                return .init(value: false)
        }
    }

}

extension SignalProducer where Error == Never {
    
    func send<StoreValue>(store: Store<StoreValue, Value>) -> Disposable? {
        return startWithValues { action in
            store.send(action)
        }
    }
    
}

