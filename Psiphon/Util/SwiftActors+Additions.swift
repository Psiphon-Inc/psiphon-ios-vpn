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
import SwiftActors
import Promises
import ReactiveSwift

/// For the first time a message (of type `PromiseMessage`) is sent, performs computation ( by calling`action`) only once.
/// While the computation is ongoing, it accumulates `Promise` objects in any other `PromiseMessage` that are sent.
/// Once the computation has finished (by sending the message that is of type `ResultMessage`), all the accumulated promises
/// are fulfilled.
///
/// - Note: To not lose this behavior on an Actor, make sure that it is composed with the append `<>` operator.
///
/// - Parameter promises: Promises are collected here recursively. Caller should not need to change this parameter.
///
/// - Parameter effect: Action that is performed only once.
///
/// - Parameter msgPromiseProjection: A projections that returns `Promise` object that is embedded in
/// message of type `PromiseMessage`. Should return `.none` if the message passed in is not the expected message.
///
/// - Parameter resultPromiseProjection: A projections that returns `Promise` object that is embedded in
/// message of type `ResultMessage`. Should return `.none` if the message passed in is not the expected message.
///
///
func promiseAcc<PromiseMessage: Message, ResultMessage: Message, PromiseType>(
    promises: [Promise<PromiseType>] = [],
    effect: @escaping () -> Void,
    _ requestPromisePath: KeyPath<PromiseMessage, Promise<PromiseType>?>,
    _ resultPromisePath: KeyPath<ResultMessage, PromiseType?>
) -> ActionHandler {
    return { msg -> ActionResult in
        switch msg {
        case let msg as PromiseMessage:
            guard let promise = msg[keyPath: requestPromisePath] else {
                return .unhandled
            }

            // Applies the side-effect if this the first message of its type.
            if promises.count == 0 {
                effect()
            }

            return .action(promiseAcc(promises: promises + [promise], effect: effect,
                                      requestPromisePath, resultPromisePath))

        case let msg as ResultMessage:
            guard let result = msg[keyPath: resultPromisePath] else {
                return .unhandled
            }

            // Note on Promises library:
            // Promises library does not allow fulfilling a promise with type `Error`.
            // i.e. instead of fulling the promise with type Error, it rejects the promise with
            // the provided value.
            // To be explicit about this, we switch on the type of `result` here.
            switch result {
            case let result as Error:
                for promise in promises {
                    promise.reject(result)
                }
            default:
                for promise in promises {
                    promise.fulfill(result)
                }
            }

            return .action(promiseAcc(promises: [], effect: effect,
                                      requestPromisePath, resultPromisePath))

        default:
            return .unhandled
        }
    }
}

protocol TypedInput {
    associatedtype InputType: Message
}

/// Represents output of a state machine.
public protocol OutputProtocol {
    associatedtype OutputType: Equatable
    associatedtype OutputErrorType: Equatable & Error

    typealias OutputSignal = Signal<OutputType, OutputErrorType>
}

extension OutputProtocol {

    /// From `ReactiveSwift`:
    /// Creates a `Signal` that will be controlled by sending events to an
    /// input observer.
    ///
    /// - Note: The `Signal` will remain alive until a terminating event is sent
    ///         to the input observer, or until it has no observers and there
    ///         are no strong references to it.
    ///
    /// - Parameters:
    ///   - disposable: An optional disposable to associate with the signal, and
    ///                 to be disposed of when the signal terminates.
    ///
    /// - Returns: A 2-tuple of the output end of the pipe as `Signal`, and the input end
    ///            of the pipe as `Signal.Observer`.
    static func makePipe(disposable: Disposable? = nil)
        -> (output: OutputSignal, input: OutputSignal.Observer) {
            return OutputSignal.pipe(disposable: disposable)
    }

}

// MARK: Typed Actor

/// Wrapper around an `Actor` and the message type it accepts.
/// This allows `tell` and `!` to be used on this type in a type-safe manner.
/// - Important: This class only holds a weak refrence to the provided `ActorRef`.
final class TypedActor<A: Message> {
    private weak var ref: ActorRef?
    private let transformer: (A) -> Message

    init(ref: ActorRef?, transformer: @escaping (A) -> Message) {
        self.ref = ref
        self.transformer = transformer
    }

    func tell(message: A) {
        ref?.tell(message: transformer(message))
    }

    func tell(message: SystemMessage) {
        ref?.tell(message: message)
    }

    func projection<B: Message>(_ f: @escaping (B) -> A) -> TypedActor<B> {
        return TypedActor<B>(ref: self.ref) { [self] (message: B) -> Message in
            return self.transformer(f(message))
        }
    }

    static func from<T: Actor & TypedInput>(
        ref: ActorRef, type: T.Type
    ) -> TypedActor<T.InputType> {
        return TypedActor<T.InputType>(ref: ref, transformer: id)
    }

    static func from<T: Actor & TypedInput>(
        actor: T
    ) -> TypedActor<T.InputType> {
        return TypedActor<T.InputType>(ref: actor, transformer: id)
    }
}


func ! <A>(lhs: TypedActor<A>, rhs: A) {
    lhs.tell(message: rhs)
}

func ! <A>(lhs: TypedActor<A>, rhs: SystemMessage) {
    lhs.tell(message: rhs)
}

extension Actor where Self: TypedInput {

    var typedSelf: TypedActor<Self.InputType> {
        .from(actor: self)
    }

}

// MARK: Observable Actor

final class ObservableActor<T: Actor & OutputProtocol & TypedInput, A: Message>
where T.OutputErrorType == Never {

    var actor: TypedActor<A>?
    var output: T.OutputSignal { pipe.output }

    private let (lifetime, token) = Lifetime.make()
    private let pipe = T.OutputSignal.pipe()
    private var actorOutputDisposable: Disposable? = nil

    /// Creates a new actor with the give `ActorBuidler`
    /// - Note: Calls `destroy` before creating the new actor.
    /// - Important: This immediately replaces the current actor, and disconencts it's output pipe.
    func create(_ builder: ActorBuilder,
                parent: ActorRefFactory,
                transform: @escaping (A) -> T.InputType,
                propsBuilder: (T.OutputSignal.Observer) -> Props<T>) {

        guard actorOutputDisposable == nil else {
            fatalError("It is an error to call create more than once on PipedActor")
        }

        let (actorOutput, actorInput) = T.OutputSignal.pipe()
        self.actor = builder.makeActor(parent, propsBuilder(actorInput))
            .projection(transform)

        // Pipes only `Values` from actorOutput into the wrapper pipe, during the lifetime
        // of this wrapper object.
        actorOutputDisposable = actorOutput.take(during: lifetime).observe { event in
            if case .value = event {
                self.pipe.input.send(event)
            }
        }
    }

    deinit {
        pipe.input.sendCompleted()
    }

}

/// MutableObservableActor output always starts with `.none` value, and sends `.none` when it is destoryed.
final class MutableObservableActor<T: Actor & OutputProtocol & TypedInput, A: Message>
where T.OutputErrorType == Never {

    var actor: TypedActor<A>? = nil
    var output: Signal<T.OutputType?, Never> { pipe.output }

    private let (lifetime, token) = Lifetime.make()
    private let pipe = Signal<T.OutputType?, Never>.pipe()
    private var actorOutputDisposable: Disposable? = nil

    init() {
        self.pipe.input.send(value: .none)
    }

    /// Creates a new actor immediately with the give `ActorBuidler`.
    /// - Note: This function is a no-op if actor is already created (but not destroyed yet by calling `destroy`).
    /// - Important: This immediately replaces the current actor, and disconencts it's output pipe.
    func create(_ builder: ActorBuilder,
                parent: ActorRefFactory,
                transform: @escaping (A) -> T.InputType,
                propsBuilder: @escaping (T.OutputSignal.Observer) -> Props<T>) {

        guard self.actor == nil else {
            return
        }

        let (actorOutput, actorInput) = T.OutputSignal.pipe()

        // Pipes only `Values` from actorOutput into the wrapper pipe, during the lifetime
        // of this wrapper object.
        // Note that actorOuput should be subscribed to before creating the actor, otherwise,
        // some events might be missed.
        actorOutputDisposable = actorOutput.take(during: self.lifetime).observe { event in
            if case .value(let eventValue) = event {
                self.pipe.input.send(value: eventValue)
            }
        }

        self.actor = builder.makeActor(parent, propsBuilder(actorInput)).projection(transform)
    }

    /// Sends `poisonPill` message to the actor, and disconnects it's  output pipe from  the wrapper's pipe.
    func destroy() {
        self.actor? ! .poisonPill(nil)
        self.actorOutputDisposable?.dispose()
        self.actorOutputDisposable = nil
        self.actor = nil
        self.pipe.input.send(value: .none)
    }

    deinit {
        pipe.input.sendCompleted()
    }

}


@propertyWrapper
final class ActorState<Value> {
    private var passthrough: Signal<Value, Never>.Observer? = nil
    private let (output, input) = Signal<Value, Never>.pipe()

    var wrappedValue: Value {
        didSet {
            input.send(value: wrappedValue)
            passthrough?.send(value: wrappedValue)
        }
    }

    var projectedValue: ActorState {
        return self
    }

    var observable: Signal<Value, Never> {
        output
    }

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    func setPassthrough(_ pipeOut: Signal<Value, Never>.Observer) {
        self.passthrough = pipeOut
        self.passthrough!.send(value: wrappedValue)
    }

    deinit {
        passthrough?.sendCompleted()
        input.sendCompleted()
    }
}


/// Represents state that should only changed on the main thread.
@propertyWrapper
public final class State<Value> {
    private let passthroughSubject = Signal<Value, Never>.pipe()
    private lazy var sharedProducer = SignalProducer<Value, Never>.init(value: self.wrappedValue)

    public var wrappedValue: Value {
        didSet { // TODO: is willSet more correct to use?
            if Current.debugging.mainThreadChecks {
                precondition(Thread.isMainThread, "state can only be set from the main thread")
            }
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


class ObjCDelegate: NSObject {}


class PromiseDelegate<T>: ObjCDelegate {

    let promise: Promise<T>

    override init() {
        self.promise = Promise<T>.pending()
    }
}


class ActorDelegate: ObjCDelegate {
    internal unowned let actor: ActorRef

    init(replyTo: ActorRef) {
        actor = replyTo
    }
}

// MARK: Combinators

/// Combines behaviors with the alternative operator.
func alternate(_ va: Behavior...) -> Behavior {
    let behaviors = NonEmpty(array: va)!
    var combined = behaviors.head
    for behavior in behaviors.tail {
        combined = behavior <|> combined
    }
    return combined
}

extension TypedInput {

    func forwarder<A>(_ actor: TypedActor<A>, message local: KeyPath<InputType, A?>) -> Behavior {
        behavior {
            guard let msg = $0 as? InputType else {
                return .unhandled
            }

            guard let localMessage = msg[keyPath: local] else {
                return .unhandled
            }

            actor ! localMessage
            return .same
        }
    }


    func forwarder<T, A>(_ wrapper: ObservableActor<T, A>,
                      message local: KeyPath<InputType, A?>) -> Behavior {
        behavior {
            guard let msg = $0 as? InputType else {
                return .unhandled
            }

            guard let localMessage = msg[keyPath: local] else {
                return .unhandled
            }

            wrapper.actor? ! localMessage
            return .same
        }
    }

    func forwarder<T, A>(_ wrapper: MutableObservableActor<T, A>,
                         message local: KeyPath<InputType, A?>) -> Behavior {
        behavior {
            guard let msg = $0 as? InputType else {
                return .unhandled
            }

            guard let localMessage = msg[keyPath: local] else {
                return .unhandled
            }

            guard let actor = wrapper.actor else {
                return .unhandled
            }

            actor ! localMessage
            return .same
        }
    }

}

