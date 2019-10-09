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

struct Services {

    fileprivate let subscriptionStateSubject =
        ReplaySubject<SubscriptionState>.create(bufferSize: 1)

    fileprivate let iapActorRelay = BehaviorSubject<ActorRef?>(value: .none)

    fileprivate let psiCashRelay = BehaviorSubject<PsiCashActorPublisher?>(value: .none)

    fileprivate let landingPageRelay = BehaviorSubject<ActorRef?>(value: .none)

    var subscriptionState: Observable<SubscriptionState> { subscriptionStateSubject }
    var iapActor: Observable<ActorRef?> { iapActorRelay }
    var psiCash: Observable<PsiCashActorPublisher?> { psiCashRelay }
    var landingPage: Observable<ActorRef?> { landingPageRelay }
}


class AppRoot: Actor {

    struct Params {
        let actorBuilder: ActorBuilder
        let sharedDB: PsiphonDataSharedDB
        let userConfigs: UserDefaultsConfig
        let appBundle: Bundle
        let notifier: Notifier
        let vpnManager: VPNManager
        let vpnStatus: BehaviorSubject<NEVPNStatus>
        let initServices: Services
    }

    var context: ActorContext!
    let param: Params

    // Services
    private var iapActorCtx: ServiceContext<ActorRef?>
    private var psiCashCtx: ServiceContext<PsiCashActorPublisher?>
    private var landingPageCtx: ServiceContext<ActorRef?>

    lazy var receive = behavior { [unowned self] in
        switch $0 {
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
                    fatalError("LandingPageActor terminated")
                case .inAppPurchase:
                    self.iapActorCtx = self.iapActorCtx.new(.none)
                case .subscription:
                    fatalError("SubscriptionActor terminated")
                }
            }

        default: return .unhandled($0)
        }

        return .same
    }

    required init(_ param: Params) {
        self.param = param
        iapActorCtx = .init(subject: param.initServices.iapActorRelay, value: .none)
        psiCashCtx = .init(subject: param.initServices.psiCashRelay, value: .none)
        landingPageCtx = .init(subject: param.initServices.landingPageRelay, value: .none)
    }

    func preStart() {
        createChild(.landingPage)
        createChild(.inAppPurchase)
    }

    func createChild(_ actorType: AppActorType) {
        guard case .none = self.getChild(actorType) else {
            return
        }

        switch actorType {
        case .psiCash:
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

        case .inAppPurchase:
            let subscriptionActorParam = makeSubscriptionActorParam(from: self.param)
            let props = Props(IAPActor.self,
                              param: IAPActor.Params(actorBuilder: self.param.actorBuilder,
                                                     appBundle: self.param.appBundle,
                                                     subscriptonActorParam: subscriptionActorParam),
                              qos: .userInteractive)


            let actor = self.param.actorBuilder.makeActor(self, props,
                                                          type: .inAppPurchase)

            self.context.watch(actor)

            /// `PsiCashActor` is created and stopped based on the subscription status.
            self.iapActorCtx = self.iapActorCtx.new(actor, dispose: { _ -> Disposable in
                self.param.initServices.subscriptionState.subscribe(onNext: { subscriptionState in
                    switch subscriptionState {
                    case .subscribed(_):
                        self.getChild(.psiCash)? ! .poisonPill
                    case .notSubscribed:
                        self.createChild(.psiCash)
                    case .unknown:
                        // No-op
                        break
                    }
                })
            })

        case .subscription:
            fatalError("SubscriptionActor not directly created by AppRoot")
        }
    }

    func getChild(_ type: AppActorType) -> ActorRef? {
        self.context.children[type]
    }

}

/// Create `SubscriptionActor` params from `AppRoot` params.
fileprivate func makeSubscriptionActorParam(from param: AppRoot.Params) -> SubscriptionActor.Param {
    SubscriptionActor.Param(publisher: param.initServices.subscriptionStateSubject,
                            notifier: param.notifier,
                            sharedDB: param.sharedDB,
                            userDefaultsConfig: param.userConfigs)
}

/// `ServiceContext` is a wrapper around a service (most typically an `ActorRef` or `ActorPublisher`),
/// the `BehaviorSubject` that that service is published on, and an optional `Disposable` reference.
///
/// - Attention: `ServiceContext`assumes ownership of the subject, no other object should publish on that subject.
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

    func new(_ value: Service,
             dispose: ((Service) -> Disposable)? = .none) -> ServiceContext<Service> {
        subject.onNext(value)
        disposable?.dispose()

        return ServiceContext(subject: subject, value: value, dispose: dispose)
    }

}
