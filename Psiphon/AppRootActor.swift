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
import ReactiveSwift
import Promises
import StoreKit

final class AppRootActor: Actor, OutputProtocol, TypedInput {
    typealias OutputType = State
    typealias OutputErrorType = Never
    typealias InputType = Action

    let logType = LogType("AppRootActor")

    struct Params {
        let pipeOut: Signal<OutputType, OutputErrorType>.Observer
    }

    enum Action: Message {
        case landingPage(LandingPageActor.Action)
        case psiCash(PsiCashActor.PublicAction)
        case inAppPurchase(IAPActor.Action)

        // TODO: private actor action.
        case verifyPsiCashConsumable(PsiCashConsumableTransaction)
    }

    fileprivate enum PrivateAction: AnyMessage {
        case subscription(SubscriptionState)
        case consumableVerified(PsiCashConsumableTransaction)
    }

    struct State: Equatable {
        let psiCash: PsiCashActor.State?
        let iap: IAPActor.OutputState
    }

    var context: ActorContext!
    private let (lifetime, token) = Lifetime.make()

    private var psiCash = MutableObservableActor<PsiCashActor, PsiCashActor.PublicAction>()
    private var iapActor = ObservableActor<IAPActor, IAPActor.Action>()
    private var landingPageActor: TypedActor<LandingPageActor.Action>!

    private var pendingPsiCashConsumable: PsiCashConsumableTransaction? = nil

    private lazy var forwardBehavior = alternate(
        forwarder(self.psiCash, message: \Action.psiCashAction),
        forwarder(self.iapActor, message: \Action.inAppPurchaseAction))

    private lazy var defaultBehavior = behavior { [unowned self] in
        switch $0 {
        case let msg as Action:
            switch msg {
            case .landingPage(.open(let url)):
                // Landing page open action is handled manually.
                self.modifyLandingPageAndOpen(url)
                return .same

            case .landingPage(.reset):
                // Forwards the reset message.
                self.landingPageActor ! .reset
                return .same

            case .psiCash:
                // Drops the message if PsiCash actor is not active.
                return .same

            case .inAppPurchase:
                return .unhandled

            case .verifyPsiCashConsumable(let psiCashConsumable):
                guard self.pendingPsiCashConsumable == nil else {
                    return .same
                }
                self.pendingPsiCashConsumable = psiCashConsumable
                self.psiCash.actor? ! .pendingPsiCashIAP
                self.lifetime += verifyConsumable(self.psiCash, psiCashConsumable)
                    .startWithValues { _ in
                        self ! PrivateAction.consumableVerified(psiCashConsumable)
                }
                return .same

            }

        case let msg as PrivateAction:
            switch msg {
            case .subscription(let subscriptionState):
                switch subscriptionState {
                case .subscribed(_), .notSubscribed:
                    // If PsiCashActor is not created yet, it creates it,
                    // otherwise it is sent a `userSubscribed` message.
                    if let psiCashActor = self.psiCash.actor {
                        psiCashActor ! .userSubscription(subscriptionState.isSubscribed)
                    } else {
                        self.makePsiCash(userSubscribed: subscriptionState.isSubscribed)
                    }
                    return .same
                case .unknown:
                    // No-op if subscription state is not known yet.
                    return .same
                }

            case .consumableVerified(let psiCashConsumable):
                PsiFeedbackLogger.info(withType: self.logType,
                                       json: ["event": "verified psicash consumable"])
                self.pendingPsiCashConsumable = nil
                self.iapActor.actor? ! .verifiedConsumableTransaction(psiCashConsumable)
                self.psiCash.actor? ! .refreshState(reason: .psiCashIAP, promise:nil)
                return .same
            }

        case let msg as NotificationMessage:
            switch msg {
            case .terminated(let actor):
                fatalError("'\(actor.name)' terminated unexpectedly")
            }
            
        default: return .unhandled
        }
    }

    lazy var receive = self.defaultBehavior <|> self.forwardBehavior

    required init(_ param: Params) {
        // Combines result from all child actors, and drains it into output (`self.param.output`).
        self.lifetime +=
            Signal.combineLatest(self.psiCash.output, self.iapActor.output)
                .map(State.init(psiCash: iap:))
                .skipRepeats()
                .observe(param.pipeOut)

        // Creates a feedback loop by listening to IAPActor subscription output, and sending
        // messages to self.
        self.lifetime += iapActor.output.map {
            iapState -> PrivateAction? in
            return .subscription(iapState.subscription)
        }
        .tell(actor: self)
    }
    
    func preStart() {
        makeLandingPageActor()
        makeIAP()
    }

    func modifyLandingPageAndOpen(_ url: RestrictedURL) {
        let promise = Promise<RestrictedURL>.pending()

        // Asks PsiCash to modify the landing page if it's actor exists
        if let psiCashActor = self.psiCash.actor {
            psiCashActor ! .modifyLandingPage(url, promise)
        } else {
            promise.fulfill(url)
        }

        promise.then { modifiedURL in
            self.landingPageActor ! .open(modifiedURL)
        }.catch { error in
            fatalError("Landing page promise rejected unexpectedly '\(error)'")
        }
    }

}

private extension AppRootActor {

    /// Makes PsiCashActor and binds an event stream to it. Updates `psiCashWrapper`.
    /// - Note: No-op if actor is not destroyed after the first `create` call.
    func makePsiCash(userSubscribed: Bool) {
        self.psiCash.create(Current.actorBuilder,
                            parent: self,
                            transform: { .public($0) },
                            propsBuilder: { input in
                                Props(PsiCashActor.self,
                                      param: PsiCashActor.Params(
                                        initiallySubscribed: userSubscribed,
                                        pipeOut: input),
                                      qos: .userInteractive)
        })
    }

    /// Makes IAPActor and updates `iapWrapper`.
    func makeIAP() {
        let selfProjection = typedSelf.projection {
            .verifyPsiCashConsumable($0)
        }

        self.iapActor.create(Current.actorBuilder,
                                  parent: self,
                                  transform: id,
                                  propsBuilder: { input in
                                    Props(IAPActor.self,
                                          param: IAPActor.Params(
                                            pipeOut: input,
                                            consumableTxObserver: selfProjection),
                                          qos: .userInteractive)
        })
    }

    func makeLandingPageActor() {
        let props = Props(LandingPageActor.self,
                          param: (),
                          qos: .userInteractive)

        self.landingPageActor = Current.actorBuilder.makeActor(self, props)
    }
    
}
