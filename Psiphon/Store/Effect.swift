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

public protocol EffectObserver {
    associatedtype Value
    func fulfill(value: Value)
}

extension Signal.Observer: EffectObserver {

    public func fulfill(value: Value) {
        self.send(value: value)
        self.sendCompleted()
    }
    
}

public typealias Effect<A> = SignalProducer<A, Never>

extension Effect where Value == Never {
    
    public func mapNever<Mapped>() -> Effect<Mapped> {
        return self.map { _ -> Mapped in } as! SignalProducer<Mapped, Never>
    }
    
}

extension Effect {
    
    /// Ignores all values emitted by `self`, and conforms the returned signal `Value` type to the call-site context.
    /// Returned effect does not emit any values.
    public func fireAndForget<Mapped>() -> Effect<Mapped> {
        return self.then(Effect<Mapped>.fireAndForget(work: { () -> Void in }))
            as! SignalProducer<Mapped, Never>
    }
    
    public func sink(
        receiveCompletion: @escaping () -> Void,
        receiveValues: @escaping (Value) -> Void,
        feedbackLogger: FeedbackLogger
    ) -> Disposable? {
        return self.start { event in
            switch event {
            case .value(let value):
                receiveValues(value)
            case .completed:
                receiveCompletion()
            case .interrupted:
                feedbackLogger.fatalError("Unexpected effect interruption")
            case .failed(_):
                feedbackLogger.fatalError("Effect failed")
            }
        }
    }
    
    /// A safer work-around for `Effect.init(_ startHandler:)`.
    /// The async work is only given access to the `fulfill(value:)` function of the `Signal.Observer`,
    /// and hence the returned Effect is completed as long as the `fulfill(value:)` function is called.
    public static func deferred(
        work: @escaping (@escaping (Value) -> Void) -> Void
    ) -> Effect<Value> {
        Effect { observer, _ in
            work(observer.fulfill(value:))
        }
    }
    
    public static func fireAndForget(work: @escaping () -> Void) -> Effect<Value> {
        Effect { observer, _ in
            if Debugging.mainThreadChecks {
                precondition(Thread.isMainThread, "action not called on main thread")
            }
            work()
            observer.sendCompleted()
        }
    }
    
}

func absurd<A>(_ never: Never) -> A {}

func erase<A>(_ value: A) -> () { () }
func erase<A>(_ value: A) -> Unit { .unit }
