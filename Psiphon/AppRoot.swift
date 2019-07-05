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

protocol AppState: AnyMessage, Equatable {}

/// TODO! maybe the actual state is not held by the AppRoot, but the VC's still hold the state.
/// and AppRoot receives these states as messages and reacts accordingly.
///
/// Or maybe the AppRoot actor holds the actual state, and is the one able to react properly.
/// SwiftAppDelegate listen to these state changes and somehow propagates that state down.
///
///
// debug remove
//struct RootState: AppState {
//    let onboarded: OnboardedState?
//}
//
//struct OnboardedState: AppState {
//    let subscribed: SubscribedState?
//}
//
//struct SubscribedState: AppState {
//    let psiCash: PsiCashState?
//}
//
//struct PsiCashState: AppState {
//    let hasEarnerToken: Bool
//}

struct Services {

    fileprivate let psiCashRelay = BehaviorSubject<PsiCashActorPublisher?>(value: .none)
    fileprivate let landingPageRelay = BehaviorSubject<ActorRef?>(value: .none)

    var psiCash: Observable<PsiCashActorPublisher?> {
        psiCashRelay
    }

    var landingPage: Observable<ActorRef?> {
        landingPageRelay
    }

}

class AppRoot: Actor {
    typealias ParamType = Params

    struct Params {
        let actorBuilder: ActorBuilder
        let sharedDB: PsiphonDataSharedDB
        let vpnManager: VPNManager
        let vpnStatus: BehaviorSubject<NEVPNStatus>
        let initServices: Services
    }

    enum ServiceType: String, AnyMessage {
        case psiCash
        case landingPage
    }

    var context: ActorContext!
    let param: Params

    // Services
    private var psiCashCtx: ServiceContext<PsiCashActorPublisher>
    private var landingPageCtx: ServiceContext<ActorRef>

    lazy var receive = behavior { [unowned self] in

        switch $0 {

        case let msg as ServiceType:

            guard case .none = self.context.children[msg] else {
                throw AppRootErrors.alreadyRegistered
            }

            switch msg {
            case .psiCash:
                let publisher = ReplaySubject<PsiCashActor.PublishedType>.create(bufferSize: 1)
                let props = Props(PsiCashActor.self,
                                  param: PsiCashActor.Params(publisher: publisher,
                                                             vpnManager: self.param.vpnManager))
                let actor = self.param.actorBuilder.makeActor(self, props, serviceType: .psiCash)

                self.context.watch(actor)

                self.psiCashCtx.new(PsiCashActorPublisher(actor: actor, publisher: publisher))
                { psiCashActorPublisher -> Disposable in
                    self.param.vpnStatus.filter { $0 == .connected }
                    .subscribe(onNext: { _ in
                        psiCashActorPublisher.actor ! PsiCashActor.Action.refreshState
                    })
                }

            case .landingPage:
                let params = LandingPageActor.Params(psiCash: self.psiCashCtx.service,
                                                     sharedDB: self.param.sharedDB,
                                                     vpnManager: self.param.vpnManager,
                                                     vpnStatus: self.param.vpnStatus)

                let props = Props(LandingPageActor.self,
                                  param: params,
                                  qos: .userInteractive)

                let actor = self.param.actorBuilder.makeActor(self, props,
                                                              serviceType: .landingPage)

                self.context.watch(actor)
                self.landingPageCtx.new(actor)

            }

            // TODO! Separate this as a thing
        case let msg as NotificationMessage:

            switch msg {
            case .terminated(let actor):
                // TODO! match by reference, not by name
                guard let serviceType = ServiceType(rawValue: actor.name) else {
                    return .unhandled(msg)
                }

                switch serviceType {
                case .psiCash:
                    self.psiCashCtx.terminate()
                case .landingPage:
                    self.landingPageCtx.terminate()
                }
            }

        default: return .unhandled($0)
        }

        return .same
    }

    required init(_ param: Params) {
        self.param = param
        psiCashCtx = ServiceContext<PsiCashActorPublisher>(relay: param.initServices.psiCashRelay)
        landingPageCtx = ServiceContext<ActorRef>(relay: param.initServices.landingPageRelay)
    }

}

fileprivate struct ServiceContext<Service> {

    /// - Important: RxSwift doesn't have a relay type such as https://github.com/JakeWharton/RxRelay
    ///              It's an error to call `onCompleted` and `onError` on this object.
    private let relay: BehaviorSubject<Service?>
    private var disposable: Disposable? {
        didSet {
            oldValue?.dispose()
        }
    }

    var service: Observable<Service?> {
        return relay
    }

    init(relay: BehaviorSubject<Service?>) {
        self.relay = relay
        disposable = .none
    }

    mutating func new(_ value: Service, dispose: ((Service) -> Disposable)? = .none) {
        relay.onNext(value)

        if let dispose = dispose {
            disposable = dispose(value)
        } else {
            disposable = .none
        }
    }

    mutating func terminate() {
        relay.onNext(.none)
        disposable?.dispose()
        disposable = .none
    }

}

protocol ActorBuilder {
    func makeActor<A>(_ parent: ActorRefFactory, _ props: Props<A>,
                      serviceType: AppRoot.ServiceType) -> ActorRef
}

struct DefaultActorBuilder: ActorBuilder {

    func makeActor<A>(_ parent: ActorRefFactory, _ props: Props<A>,
                      serviceType: AppRoot.ServiceType) -> ActorRef {
        return parent.spawn(props, name: serviceType.rawValue)
    }

}
