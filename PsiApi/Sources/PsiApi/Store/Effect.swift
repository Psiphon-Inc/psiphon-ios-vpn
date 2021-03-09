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
import Utilities

public protocol Dispatcher {
    
    // Compatibility with ReactiveSwift.Scheduler
    var rxScheduler: ReactiveSwift.Scheduler? { get }
    
    func dispatch(_ action: @escaping () -> Void)
    
}

/// Represents a scheduler that performs its work on the main dispatch queue.
public struct MainDispatcher: Dispatcher {
    
    public var rxScheduler: Scheduler? {
        backingScheduler
    }
    
    private let backingScheduler: QueueScheduler
    
    public init() {
        backingScheduler = .main
    }
    
    public func dispatch(_ action: @escaping () -> Void) {
        backingScheduler.schedule(action)
    }
    
}

/// Represents a scheduler that performs its work outside the main dispatch queue.
public struct GlobalDispatcher: Dispatcher {
    
    public var rxScheduler: Scheduler? {
        backingScheduler
    }
    
    private let backingScheduler: QueueScheduler
    
    public init(qos: DispatchQoS, name: String) {
        backingScheduler = QueueScheduler(qos: qos, name: name, targeting: nil)
    }
    
    public func dispatch(_ action: @escaping () -> Void) {
        backingScheduler.schedule(action)
    }
    
}

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
                return
            case .failed(_):
                feedbackLogger.fatalError("Effect failed")
                return
            }
        }
    }
    
    /// A safer work-around for `Effect.init(_ startHandler:)`.
    /// If a `dispatcher` is given, `work` will be dispatched on it,
    /// otherwise `work` is called on whatever dispatch queue the returned Effect is running on.
    public static func deferred(
        dispatcher: Dispatcher? = nil,
        work: @escaping (@escaping (Value) -> Void) -> Void
    ) -> Effect<Value> {
        Effect { observer, _ in
            if let dispatcher = dispatcher {
                dispatcher.dispatch {
                    work(observer.fulfill(value:))
                }
            } else {
                work(observer.fulfill(value:))
            }
        }
    }
    
    /// Runs `work` inside the effect. Result of `work` is then emitted,
    /// and the returned signal completed.
    public static func deferred(
        work: @escaping () -> Value
    ) -> Effect<Value> {
        Effect { observer, _ in
            observer.fulfill(value: work())
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

public func absurd<A>(_ never: Never) -> A {}

public func erase<A>(_ value: A) -> () { () }
public func erase<A>(_ value: A) -> Utilities.Unit { .unit }
