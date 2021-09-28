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

public struct TimeoutError: Error {}

// TODO: replace with Pair type.
public struct Combined<Value> {
    public let previous: Value
    public let current: Value
    
    public init(previous: Value, current: Value) {
        self.previous = previous
        self.current = current
    }
}

/// A value that represents either the next value in a stream of values
/// or that the signal should be completed. Allows for an inclusive
/// `take(while:)` operator, e.g.:
///
///     .flatMap(.latest) { (done: Bool) -> SignalProducer<SignalTermination<String>, Never> in
///         if done {
///             // End the stream.
///             return SignalProducer(value:.terminate).prefix(value:.value("last value emitted"))
///         } else {
///             return SignalProducer(value:.value("next value emitted"))
///         }
///     }
///     .take(while: { (signalTermination: SignalTermination<String>) -> Bool in
///         // Forwards values while the `.terminate` value has not been emitted.
///         guard case .value(_) = signalTermination else {
///             return false
///         }
///         return true
///     })
///     .map { (signalTermination: SignalTermination<String>) -> String in
///         guard case let .value(x) = signalTermination else {
///             // Will never happen.
///             fatalError()
///         }
///         return x
///     }
///
/// - Note: can be replaced by an inclusive `take(while:)` operator.
public enum SignalTermination<Value> {

    /// The next value in the stream.
    case value(Value)

    /// Value which indicates that the signal should be completed.
    case terminate

}

extension Signal where Error == Never {

    public func observe<A>(store: Store<A, Value>) -> Disposable? {
        return self.observeValues { [unowned store] (value: Signal.Value) in
            store.send(value)
        }
    }

}

extension Signal where Error == Never {
    
    /// Emits `defaultValue` and completes the signal, if `shouldWait` has not returned `false`
    /// for any of the values emitted upstream.
    /// - Parameter defaultValue: Default value that is emitted if `shouldWait` never
    ///  returns `false` within `timeout`.
    /// - Parameter timeout: Timeout interval within which if `shouldWait` doesn't returne
    /// `false`, `defaultValue` is emitted.
    /// - Parameter shouldWait: Called for every upstream value emitted, if it returns `false`
    /// the upstream value is emitted and the returned signal is completed. If `shouldWait` never
    /// returns `false` within `timeout`, then `defaultValue` is emitted and the signal completed.
    public func shouldWait(
        upto timeout: DispatchTimeInterval,
        otherwiseEmit defaultValue: Value,
        shouldWait: @escaping (Value) -> Bool
    ) -> Signal<Value, Never> {
        precondition(timeout != .never, "Unexpected '.never' timeout")
        
        return self.filter { !shouldWait($0) }
        .take(first: 1)
        .timeout(after: timeout.toDouble()!, raising: TimeoutError(), on: QueueScheduler.main)
        .flatMapError { anyError -> SignalProducer<Value, Error> in
            return SignalProducer(value: defaultValue)
        }
        
    }
    
}

extension SignalProducer {
    
    public static func neverComplete(value: Value) -> Self {
        SignalProducer { observer, _ in
            observer.send(value: value)
        }
    }
    
    /// A `SignalProducerConvertible` version of `combinePrevious(_:)`
    public func combinePrevious(initial: Value) -> SignalProducer<Combined<Value>, Error> {
        self.combinePrevious(initial)
            .map { (combined: (Value, Value)) -> Combined<Value> in
                Combined(previous: combined.0, current: combined.1)
        }
    }
    
    /// A safer work-around for `SignalProducer.init(_ startHandler:)`.
    /// The async work is only given access to the `fulfill(value:)` function of the `Signal.Observer`,
    /// and hence the returned Effect is completed as long as the `fulfill(value:)` function is called.
    public static func async(
        work: @escaping (@escaping (Result<Value, Error>) -> Void) -> Void
    ) -> SignalProducer<Value, Error> {
        
        SignalProducer { (observer: Signal<Value, Error>.Observer, _) in
            
            work({ (result: Result<Value, Error>) in
                
                switch result {
                case let .success(value):
                    observer.send(value: value)
                    observer.sendCompleted()
                    
                case let .failure(failure):
                    observer.send(error: failure)
                }
                
            })
            
        }
        
    }
    
    /// Maps a `SignalProducer<Value, Error>` to `SignalProducer<U,  Never>`,
    /// using provided transform function `Result<Value, Error> -> U`.
    /// `U` is typically a `Result` value, but could be anything.
    public func mapBothAsResult<U>(
        _ transform: @escaping (Result<Value, Error>) -> U
    ) -> SignalProducer<U, Never> {
        
        self.map {
            transform(.success($0))
        }.flatMapError {
            .init(value: transform(.failure($0)))
        }
        
    }
    
}

extension SignalProducer where Error == Never {
    
    /// Emits `defaultValue` and completes the signal, if `shouldWait` has not returned `false`
    /// for any of the values emitted upstream.
    /// - Parameter defaultValue: Default value that is emitted if `shouldWait` never
    ///  returns `false` within `timeout`.
    /// - Parameter timeout: Timeout interval within which if `shouldWait` doesn't returne
    /// `false`, `defaultValue` is emitted.
    /// - Parameter shouldWait: Called for every upstream value emitted, if it returns `false`
    /// the upstream value is emitted and the returned signal is completed. If `shouldWait` never
    /// returns `false` within `timeout`, then `defaultValue` is emitted and the signal completed.
    public func shouldWait(
        upto timeout: DispatchTimeInterval,
        otherwiseEmit defaultValue: Value,
        shouldWait: @escaping (Value) -> Bool
    ) -> SignalProducer<Value, Never> {
        precondition(timeout != .never, "Unexpected '.never' timeout")
        
        return self.filter { !shouldWait($0) }
        .take(first: 1)
        .timeout(after: timeout.toDouble()!, raising: TimeoutError(), on: QueueScheduler.main)
        .flatMapError { anyError -> SignalProducer<Value, Error> in
            return SignalProducer(value: defaultValue)
        }
        
    }
    
}

extension SignalProducer where Error == Never {
    
    public func send<StoreValue>(store: Store<StoreValue, Value>) -> Disposable? {
        return startWithValues { action in
            store.send(action)
        }
    }
    
}

extension SignalProducer where Value: Collection, Error == Never {
    
    /// Sends all elements of emitted value as actions to `store` sequentially.
    public func send<StoreValue>(store: Store<StoreValue, Value.Element>) -> Disposable? {
        return startWithValues { actions in
            for action in actions {
                store.send(action)
            }
        }
    }
    
}
