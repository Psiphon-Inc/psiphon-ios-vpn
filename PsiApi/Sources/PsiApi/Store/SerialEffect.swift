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
import Utilities

public enum SerialEffectAction<Action> {
    case action(Action)
    case _effectAction(Action)
    case _effectCompleted
}

public struct SerialEffectState<Value: Equatable, Action: Equatable>: Equatable {
    public var pendingActionQueue: Queue<Action>
    public var pendingEffectActionQueue: Queue<Action>
    public var pendingEffectCompletion: Bool
    public var value: Value
 
    public init(_ initialValue: Value) {
        self.init(pendingActionQueue: Queue<Action>(),
                  pendingEffectActionQueue: Queue<Action>(),
                  pendingEffectCompletion: false,
                  value: initialValue)
    }
    
    public init(pendingActionQueue: Queue<Action>,
                pendingEffectActionQueue: Queue<Action>,
                pendingEffectCompletion: Bool,
                value: Value) {
        self.pendingActionQueue = pendingActionQueue
        self.pendingEffectActionQueue = pendingEffectActionQueue
        self.pendingEffectCompletion = pendingEffectCompletion
        self.value = value
    }
    
}

public func makeSerialEffectReducer<Value, Action: Equatable, Environment>(
    _ reducer: @escaping Reducer<Value, Action, Environment>,
    feedbackLogger: FeedbackLogger
) -> Reducer<SerialEffectState<Value, Action>, SerialEffectAction<Action>, Environment> {
    return { serialEffectState, serialEffectAction, environment in

        let actionToRun: Action
        
        switch serialEffectAction {
        case ._effectCompleted:
            guard serialEffectState.pendingEffectCompletion else {
                feedbackLogger.fatalError("Expected 'pendingEffectCompletion' to be true")
                return []
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
                    feedbackLogger.fatalError("Signal interrupted unexpectedly")
                    return ._effectCompleted
                }
            }
        ]
        
    }
}
