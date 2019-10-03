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
import RxSwift

fileprivate enum AppRootErrors: Error {
    case alreadyRegistered
}

// TODO!! remove this after done with AppRoot actor.
extension AppActorType: AnyMessage {}

struct Services {

    fileprivate let subscriptionRelay =
        BehaviorSubject<SubscriptionActorPublisher?>(value: .none)

    fileprivate let psiCashRelay = BehaviorSubject<PsiCashActorPublisher?>(value: .none)

    fileprivate let landingPageRelay = BehaviorSubject<ActorRef?>(value: .none)

    var subscription: Observable<SubscriptionActorPublisher?> { subscriptionRelay }
    var psiCash: Observable<PsiCashActorPublisher?> { psiCashRelay }
    var landingPage: Observable<ActorRef?> { landingPageRelay }

}

class AppRoot: Actor {

    struct Params {
        let actorBuilder: ActorBuilder
        let sharedDB: PsiphonDataSharedDB
        let appBundle: Bundle
        let notifier: Notifier
        let vpnManager: VPNManager
        let vpnStatus: BehaviorSubject<NEVPNStatus>
        let initServices: Services
    }

    enum Action: AnyMessage {
        case subscribed(Bool)
    }

    var context: ActorContext!
    let param: Params

    // Services
    private var subscriptionCtx: ServiceContext<SubscriptionActorPublisher?>
    private var psiCashCtx: ServiceContext<PsiCashActorPublisher?>
    private var landingPageCtx: ServiceContext<ActorRef?>

    lazy var receive = behavior { [unowned self] in

        switch $0 {

        case let msg as AppActorType:

            guard case .none = self.context.children[msg] else {
                throw AppRootErrors.alreadyRegistered
            }

            switch msg {
            case .psiCash:
                // TODO!! this publisher should comlete if the actor dies
                let publisher = ReplaySubject<PsiCashActor.PublishedType>.create(bufferSize: 1)
                let props = Props(PsiCashActor.self,
                                  param: PsiCashActor.Params(publisher: publisher,
                                                             vpnManager: self.param.vpnManager),
                                  qos: .userInteractive)
                let actor = self.param.actorBuilder.makeActor(self, props, type: .psiCash)

                self.context.watch(actor)

                self.psiCashCtx = self.psiCashCtx.new(
                    PsiCashActorPublisher(actor: actor, publisher: publisher),
                    dispose: { actorPublisher -> Disposable in
                        self.param.vpnStatus.filter { $0 == .connected }
                            .subscribe({ _ in
                                actorPublisher?.actor ! PsiCashActor.Action.refreshState(.none)
                            })
                })

            case .landingPage:
                let params = LandingPageActor.Params(psiCash: self.psiCashCtx.service,
                                                     sharedDB: self.param.sharedDB,
                                                     vpnManager: self.param.vpnManager,
                                                     vpnStatus: self.param.vpnStatus)

                let props = Props(LandingPageActor.self,
                                  param: params,
                                  qos: .userInteractive)

                let actor = self.param.actorBuilder.makeActor(self, props,
                                                              type: .landingPage)

                self.context.watch(actor)
                self.landingPageCtx = self.landingPageCtx.new(actor)

            case .subscription:
                break // TODO!! fix the mess
//                let publisher = ReplaySubject<SubscriptionActor.State>.create(bufferSize: 1)
//                let props = Props(SubscriptionActor.self,
//                                  param: SubscriptionActor.Param(publisher: publisher,
//                                                                 notifier: self.param.notifier,
//                                                                 appStoreReceipt: self.param.appBundle.appStoreReceiptURL!,
//                                                                 appBundleIdentifier: self.param.appBundle.bundleIdentifier!,
//                                                                 sharedDB: self.param.sharedDB),
//                                  qos: .userInteractive)
//
//                let actor = self.param.actorBuilder.makeActor(self, props,
//                                                              serviceType: .subscription)
//
//                let actorPublisher = SubscriptionActorPublisher(actor: actor, publisher: publisher)
//
//                self.context.watch(actor)
//                self.subscriptionCtx = self.subscriptionCtx.new(actorPublisher)
            default:
                fatalError("not implemented")
            }

            // TODO! Separate this as a thing
        case let msg as NotificationMessage:

            switch msg {
            case .terminated(let actor):
                // TODO! match by reference, not by name
                guard let serviceType = AppActorType(rawValue: actor.name) else {
                    return .unhandled(msg)
                }

                switch serviceType {
                case .psiCash:
                    self.psiCashCtx = self.psiCashCtx.new(.none)
                case .landingPage:
                    self.landingPageCtx = self.landingPageCtx.new(.none)
                case .subscription:
                    fatalError("Subscription actor terminated")
                default: fatalError("not implemented")
                }
            }

        default: return .unhandled($0)
        }

        return .same
    }

    required init(_ param: Params) {
        self.param = param
        subscriptionCtx = .init(subject: param.initServices.subscriptionRelay, value: .none)
        psiCashCtx = .init(subject: param.initServices.psiCashRelay, value: .none)
        landingPageCtx = .init(subject: param.initServices.landingPageRelay, value: .none)
    }

    func preStart() {
        self ! AppActorType.subscription
    }

}

fileprivate struct ServiceContext<Service> {

    /// - Important: RxSwift doesn't have a relay type such as https://github.com/JakeWharton/RxRelay
    ///              It's an error to call `onCompleted` and `onError` on this object.
    private let subject: BehaviorSubject<Service>
    private let disposable: Disposable?
    private let value: Service

    var service: Observable<Service> { subject }

    init(subject: BehaviorSubject<Service>, value: Service,
         dispose: ((Service) -> Disposable)? = .none) {

        self.subject = subject
        self.value = value
        self.disposable = dispose?(value)
    }

    func new(_ value: Service, dispose: ((Service) -> Disposable)? = .none) -> ServiceContext<Service> {
        subject.onNext(value)
        disposable?.dispose()

        return ServiceContext(subject: subject, value: value, dispose: dispose)
    }

}
