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

public struct Reducer<Value: Equatable, Action, Environment> {
    
    private let reducer: (inout Value, Action, Environment) -> [Effect<Action>]
    
    public init(_ reducer: @escaping (inout Value, Action, Environment) -> [Effect<Action>]) {
        self.reducer = reducer
    }
    
    public func callAsFunction(
        _ value: inout Value, _ action: Action, _ environment: Environment
    ) -> [Effect<Action>] {
        self.reducer(&value, action, environment)
    }
    
}

public extension Reducer {
    
    static func combine(_ reducers: Reducer<Value, Action, Environment>...) -> Self {
        .init { value, action, environment in
            let effects = reducers.flatMap { $0(&value, action, environment) }
            return effects
        }
    }

    
    func pullback<GlobalValue, GlobalAction, GlobalEnvironment>(
        value valuePath: WritableKeyPath<GlobalValue, Value>,
        action actionPath: WritableKeyPath<GlobalAction, Action?>,
        environment toLocalEnvironment: @escaping (GlobalEnvironment) -> (Environment)
    ) -> Reducer<GlobalValue, GlobalAction, GlobalEnvironment> {
        .init { globalValue, globalAction, globalEnv in

            // Converts GlobalAction into LocalAction accepted by `self.reducer`.
            guard let localAction = globalAction[keyPath: actionPath] else { return [] }

            let effects: [Effect<Action>] = self(&globalValue[keyPath: valuePath],
                                                 localAction,
                                                 toLocalEnvironment(globalEnv))

            // Pulls local action into global action.
            let pulledLocalEffects: [Effect<GlobalAction>] = effects.map { localEffect in
                localEffect.map { localAction -> GlobalAction in
                    var globalAction = globalAction
                    globalAction[keyPath: actionPath] = localAction
                    return globalAction
                }
            }

            return pulledLocalEffects
        }
    }
    
}


/// An event-driven state machine that runs it's effects on the main thread.
/// Can be observed from any other thread, however, events can only be sent to it on the main-thread.
public final class Store<Value: Equatable, Action> {
    public typealias OutputType = Value
    public typealias OutputErrorType = Never

    /// - Note: Accessing current value is not thread-safe.
    @State public private(set) var value: Value

    private let dispatcher: Dispatcher
    private var reducer: Reducer<Value, Action, ()>!
    private var disposable: Disposable? = .none
    private var effectDisposables = CompositeDisposable()
    
    /// Count of effects that have not completed.
    public private(set) var outstandingEffectCount = 0
    
    public init<Environment>(
        initialValue: Value,
        reducer: Reducer<Value, Action, Environment>,
        dispatcher: Dispatcher,
        environment makeEnvironment: (Store<Value, Action>) -> Environment
    ) {
        self.value = initialValue
        self.dispatcher = dispatcher
        
        let environment = makeEnvironment(self)
        self.reducer = .init { value, action, _ in
            reducer(&value, action, environment)
        }
    }
    
    private init(dispatcher: Dispatcher, initialValue: Value, reducer: Reducer<Value, Action, ()>) {
        self.reducer = reducer
        self.value = initialValue
        self.dispatcher = dispatcher
    }
    
    deinit {
        effectDisposables.dispose()
    }
    
    /// Sends action to the store asynchronously.
    /// - Note: This function is thread-safe.
    public func send(_ action: Action) {
        self.dispatcher.dispatch { [unowned self] in
            _ = syncSend(action)
        }
    }
     
    /// Sends action to the store.
    internal func syncSend(_ action: Action) -> Value {
        // Executes the reducer and collects the effects
        let effects = self.reducer(&self.value, action, ())
        
        self.outstandingEffectCount += effects.count
        
        effects.forEach { effect in
            var disposable: Disposable?
            disposable = effect.observe(on: self.dispatcher.rxScheduler!)
                .sink(
                    receiveCompletion: {
                        disposable?.dispose()
                        self.outstandingEffectCount -= 1
                    },
                    receiveValues: { [unowned self] internalAction in
                        _ = self.syncSend(internalAction)
                    }
                )
            
            self.effectDisposables.add(disposable)
        }
        
        return self.value
    }

    /// Creates a  projection of the store value and action types.
    /// - Parameter value: A function that takes current store Value type and maps it to LocalValue.
    /// - Note: `projection(value:action:)` is not thread-safe.
    public func projection<LocalValue, LocalAction>(
        value toLocalValue: @escaping (Value) -> LocalValue,
        action toGlobalAction: @escaping (LocalAction) -> Action
    ) -> Store<LocalValue, LocalAction> {
        
        // isSending tracks if the local store is sending a value
        // to the global store.
        // This is useful for avoiding multiple redundant updates
        // to the localStore's state value.
        var isSending = false
        
        let localStore = Store<LocalValue, LocalAction>(
            dispatcher: self.dispatcher,
            initialValue: toLocalValue(self.value),
            reducer: .init { localValue, localAction, _ in
                
                // Sets isSending to true
                isSending = true
                defer { isSending = false }
                
                // Local projection sends actions to the global MainStore,
                // and maps the global value to local value with `toLocalValue`.
                localValue = toLocalValue(self.syncSend(toGlobalAction(localAction)))
                
                return []
        })

        // Subscribes localStore to the value changes of the "global store",
        // due to actions outside the localStore.
        localStore.disposable = self.$value.signalProducer
            .skip(first: 1)  // Initial value is already set when localStore is constructed.
            .startWithValues { [weak localStore] newValue in
                // localStore value is already updated if isSending to the global store.
                guard !isSending else { return }
                localStore?.value = toLocalValue(newValue)
        }

        return localStore
    }

}
