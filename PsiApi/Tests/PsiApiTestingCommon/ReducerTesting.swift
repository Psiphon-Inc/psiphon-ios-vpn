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
import PsiApi
import Testing
import Utilities

func testReducer<Value, Action, Environment>(
    _ initialState: Value,
    _ action: Action,
    _ env: Environment,
    _ reducer: Reducer<Value, Action, Environment>,
    _ timeout: TimeInterval = 1.0
) -> (Value, [[Signal<Action, SignalProducer<Action, Never>.SignalError>.Event]]) {
    var nextState = initialState
    let effects = reducer(&nextState, action, env)
    let effectsResults = effects.map { $0.collectForTesting(timeout: timeout) }
    return (nextState, effectsResults)
}

struct ReducerTestResult<Value: Equatable, Action: Equatable>: Equatable {
    typealias EffectResultType = [[Signal<Action, SignalProducer<Action, Never>.SignalError>.Event]]
    
    let state: Value
    let effectsResults: EffectResultType
    
    init(_ state: Value, _ effectsResults: EffectResultType) {
        self.state = state
        self.effectsResults = effectsResults
    }
    
}

/// Tests given reducer by recursively applying actions from returned effects to the reducer until
/// no more effects are returned.
/// - Note: Applying `initialState` and `action` to `reducer` should not loop indefinitely, otherwise
/// this function will never return.
func testReducerRec<Value, Action, Environment>(
    _ initialState: Value,
    _ action: Action,
    _ env: Environment,
    _ reducer: Reducer<Value, Action, Environment>,
    _ timeoutPerActionEffect: TimeInterval = 1.0
) -> [ReducerTestResult<Value, Action>] {
    _testReducerRecHelper(initialState, [action], env, reducer)
}

fileprivate func _testReducerRecHelper<Value, Action, Environment>(
    _ initialState: Value,
    _ actions: [Action],
    _ env: Environment,
    _ reducer: Reducer<Value, Action, Environment>,
    _ timeoutPerActionEffect: TimeInterval = 1.0
) -> [ReducerTestResult<Value, Action>] {
    
    guard let first = actions.first else {
        return []
    }
    
    let (nextState, effectsResults) = testReducer(initialState, first, env,
                                                  reducer, timeoutPerActionEffect)
    
    let nextActions = effectsResults.flatMap { events in
        events.compactMap { (event: Signal<Action, SignalProducer<Action, Never>.SignalError>.Event) -> Action? in
            guard case let .value(value) = event else {
                return nil
            }
            return value
        }
    }
    
    return [ReducerTestResult(nextState, effectsResults)] +
        _testReducerRecHelper(nextState, Array(actions.dropFirst()) + nextActions,
                              env, reducer, timeoutPerActionEffect)
}
