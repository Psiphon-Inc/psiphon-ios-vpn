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
import Promises
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

public struct Effect<A> {
    public typealias Publisher = SignalProducer<A, Never>

    private let publisher: Publisher

    public init(_ publisher: Publisher) {
        self.publisher = publisher
    }

    public init(generator: @escaping (Publisher.ProducedSignal.Observer, Lifetime) -> Void) {
        self.publisher = Publisher.init(generator)
    }

    public init<T>(promise: Promise<T>, then thenExpression: @escaping (T) -> A?) {
        self.publisher = Publisher { observer, _ in
            promise.then { value in
                if let thenValue = thenExpression(value) {
                    observer.fulfill(value: thenValue)
                } else {
                    observer.sendCompleted()
                }

            }.catch { error in
                fatalError("Unexpected promise rejection: '\(error)'")
            }
        }
    }

    public func bind<B>(_ f: (Publisher) -> Effect<B>) -> Effect<B> {
        return f(self.publisher)
    }

    public func map<B>(_ f: @escaping (A) -> B) -> Effect<B> {
        return Effect<B>(publisher.map(f))
    }

    public func receiveOnMainThread() -> Effect<A> {
        return Effect(publisher.observeOnUIScheduler())
    }

    public func sink(receiveCompletion: @escaping () -> Void) -> Disposable? {
        return publisher.startWithCompleted(receiveCompletion)
    }

    public func sink(
        receiveCompletion: @escaping () -> Void,
        receiveValues: @escaping (A) -> Void
    ) -> Disposable? {

        return publisher.start { event in
            switch event {
            case .value(let value):
                receiveValues(value)
            case .completed:
                receiveCompletion()
            case .interrupted:
                fatalError("unexpected effect interruption")
            }
        }
    }

}

extension Effect {

    static func promise<Success, Failure: Error>(
        _ work: @escaping (Lifetime) -> Promise<Result<Success, Failure>>
    ) -> Effect<Result<Success, Failure>> {

        return .init { observer, lifetime in
            work(lifetime).then { result in
                observer.send(value: result)
            }.catch { error in
                fatalError("promise should fail by emitting a result")
            }
        }
    }

}

public enum EffectType<Internal, External> {
    case `internal`(Effect<Internal>)
    case external(Effect<External>)

    var internalEffect: Effect<Internal>? {
        guard case let .internal(value) = self else { return nil }
        return value
    }

    var externalEffect: Effect<External>? {
        guard case let .external(value) = self else { return nil }
        return value
    }
}

public typealias Reducer<Value, Action, ExternalAction> =
    (inout Value, Action) -> [EffectType<Action, ExternalAction>]


public func combine<Value, Action, ExternalAction>(
    _ reducers: Reducer<Value, Action, ExternalAction>...
) -> Reducer<Value, Action, ExternalAction> {
    return { value, action in
        let effects = reducers.flatMap { $0(&value, action) }
        return effects
    }
}

public func pullback<LocalValue, GlobalValue, LocalAction, GlobalAction, ExternalAction>(
    _ localReducer:
    @escaping Reducer<LocalValue, LocalAction, ExternalAction>,
    value valuePath: WritableKeyPath<GlobalValue, LocalValue>,
    action actionPath: WritableKeyPath<GlobalAction, LocalAction?>
) -> Reducer<GlobalValue, GlobalAction, ExternalAction> {
    return pullback(localReducer, value: valuePath, action: actionPath, external: id)
}

public func pullback<LocalValue, GlobalValue, LocalAction,
    GlobalAction, LocalExternalAction, ExternalAction>(
    _ localReducer:
    @escaping Reducer<LocalValue, LocalAction, LocalExternalAction>,
    value valuePath: WritableKeyPath<GlobalValue, LocalValue>,
    action actionPath: WritableKeyPath<GlobalAction, LocalAction?>,
    external toGlobalExternalAction: @escaping (LocalExternalAction) -> ExternalAction
) -> Reducer<GlobalValue, GlobalAction, ExternalAction> {
    return { globalValue, globalAction in

        // Converts GlobalAction into LocalAction accepted by `localReducer`.
        guard let localAction = globalAction[keyPath: actionPath] else { return [] }

        let effects = localReducer(&globalValue[keyPath: valuePath],
                                   localAction)

        // Pulls local action into global action.
        let pulledLocalEffects = effects.compactMap {
            $0.internalEffect
        }.map { localEffect in
            localEffect.map { localAction -> GlobalAction in
                var globalAction = globalAction
                globalAction[keyPath: actionPath] = localAction
                return globalAction
            }
        }.map { effect -> EffectType<GlobalAction, ExternalAction> in
            .internal(effect)
        }

        let externalEffects = effects.compactMap {
            let effect = $0.externalEffect
            return effect?.map { toGlobalExternalAction($0) }
        }.map { effect -> EffectType<GlobalAction, ExternalAction> in
            .external(effect)
        }

        return pulledLocalEffects + externalEffects
    }
}


/// An event-driven state machine that runs it's effects on the main thread.
/// Can be observed from any other thread, however, events can only be sent to it on the main-thread.
public final class Store<Value: Equatable, Action, ExternalAction>: OutputProtocol {
    public typealias OutputType = Value
    public typealias OutputErrorType = Never
    public typealias StoreReducer = Reducer<Value, Action, ExternalAction>

    @State public private(set) var value: Value

    private let reducer: StoreReducer
    private let externalSend: (ExternalAction) -> Void
    private var disposable: Disposable? = .none
    private var effectDisposables = CompositeDisposable()

    public init(initialValue: Value,
                reducer: @escaping StoreReducer,
                external: @escaping (ExternalAction) -> Void) {

        self.reducer = reducer
        self.externalSend = external
        self.value = initialValue
    }

    /// Sends action to the store.
    /// - Note: Stops program execution if called from threads other than the main thread.
    public func send(_ action: Action) {
        if Current.debugging.mainThreadChecks {
            precondition(Thread.isMainThread, "actions should only be sent from the main thread")
        }
        // Executes the reducer and collects the effects
        let effects = self.reducer(&self.value, action)

        effects.forEach { effectType in
            var effectDisposable: Disposable?

            switch effectType {
            case .internal(let internalEffect):
                effectDisposable = internalEffect.receiveOnMainThread()
                    .sink(receiveCompletion: {
                        effectDisposable?.dispose()
                    }, receiveValues: { [unowned self] internalAction in
                        self.send(internalAction)
                    })

                effectDisposable = internalEffect.sink {
                    effectDisposable?.dispose()
                }

            case .external(let externalEffect):
                effectDisposable = externalEffect.sink(receiveCompletion: {
                    effectDisposable?.dispose()
                }, receiveValues: { [weak self] externalAction in
                    self?.externalSend(externalAction)
                })
            }

            self.effectDisposables.add(effectDisposable)
        }

    }

    /// Creates a  projection of the store value and action types.
    /// - Parameter value: A function that takes current store Value type and maps it to LocalValue.
    public func projection<LocalValue, LocalAction, LocalExternalAction>(
        value toLocalValue: @escaping (Value) -> LocalValue,
        action toGlobalAction: @escaping (LocalAction) -> Action,
        external toGlobalExternalAction: @escaping (LocalExternalAction) -> ExternalAction
    ) -> Store<LocalValue, LocalAction, LocalExternalAction> {

        let localStore = Store<LocalValue, LocalAction, LocalExternalAction>(
            initialValue: toLocalValue(self.value),
            reducer: { localValue, localAction in
                // Local projection sends actions to the global MainStore.
                self.send(toGlobalAction(localAction))
                // Updates local stores value immediately.
                localValue = toLocalValue(self.value)
                return []
        }, external: {
            self.externalSend(toGlobalExternalAction($0))
        })

        // Subscribes localStore to the value changes of the "global store",
        // due to actions outside the localStore.
        localStore.disposable = self.$value.signalProducer.startWithValues { [weak localStore] in
            localStore?.value = toLocalValue($0)
        }

        return localStore
    }

}

public func logging<Value, Action, ExternalAction>(
    _ reducer: @escaping Reducer<Value, Action, ExternalAction>
) -> Reducer<Value, Action, ExternalAction> {
    return { value, action in
        let effects = reducer(&value, action)
        let newValue = value
        return [.external(Effect { _,_  in
            print("Action: \(action)")
            print("Value:")
            dump(newValue)
            print("---")
        })] + effects
    }
}
