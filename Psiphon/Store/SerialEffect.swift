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

enum SerialEffectAction<Action> {
    case action(Action)
    case _effectAction(Action)
    case _effectCompleted
}

struct SerialEffectState<Value: Equatable, Action: Equatable>: Equatable {
    fileprivate var pendingActionQueue: Queue<Action>
    fileprivate var pendingEffectActionQueue: Queue<Action>
    fileprivate var pendingEffectCompletion: Bool
    var value: Value

    init(_ initialValue: Value) {
        pendingActionQueue = Queue<Action>()
        pendingEffectActionQueue = Queue<Action>()
        pendingEffectCompletion = false
        value = initialValue
    }
}

func makeSerialEffectReducer<Value, Action: Equatable, Environment>(
    _ reducer: @escaping Reducer<Value, Action, Environment>
) -> Reducer<SerialEffectState<Value, Action>, SerialEffectAction<Action>, Environment> {
    return { serialEffectState, serialEffectAction, environment in

        let actionToRun: Action
        
        switch serialEffectAction {
        case ._effectCompleted:
            guard serialEffectState.pendingEffectCompletion else {
                fatalErrorFeedbackLog("Expected 'pendingEffectCompletion' to be true")
            }
            
            // Actions from pendingEffectActionQueue are prioritized over pendingEffectActionQueue.
            if let queuedAction = serialEffectState.pendingEffectActionQueue.dequeue() {
                actionToRun = queuedAction
            } else if let queuedAction = serialEffectState.pendingActionQueue.dequeue() {
                actionToRun = queuedAction
            } else {
                // There are no more actions in the queues.
                serialEffectState.pendingEffectCompletion = false
                return []
            }
            
        case ._effectAction(let action):
            guard !serialEffectState.pendingEffectCompletion else {
                serialEffectState.pendingEffectActionQueue.enqueue(action)
                return []
            }
            actionToRun = action
            
        case .action(let action):
            // Enqueues the action only if there are no effects pending completion.
            guard !serialEffectState.pendingEffectCompletion else {
                serialEffectState.pendingActionQueue.enqueue(action)
                return []
            }
            actionToRun = action
        }
        
        let returnedEffects = reducer(&serialEffectState.value, actionToRun, environment)
        serialEffectState.pendingEffectCompletion = true
        
        guard let effects = NonEmpty(array: returnedEffects) else {
            return [ Effect(value: ._effectCompleted) ]
        }
        
        var concatenatedEffect = effects.head
        for effect in effects.tail {
            concatenatedEffect = concatenatedEffect.concat(effect)
        }
        return [
            concatenatedEffect.materialize().map { event in
                switch event {
                case .value(let action):
                    return ._effectAction(action)
                case .completed:
                    return ._effectCompleted
                case .interrupted:
                    fatalErrorFeedbackLog("Signal interrupted unexpectedly")
                }
            }
        ]
        
    }
}
