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
import Promises


class LandingPageActor: Actor {
    typealias ParamType = Params

    struct Params {
        let psiCash: Observable<PsiCashActorPublisher?>
        let sharedDB: PsiphonDataSharedDB
        let vpnManager: VPNManager
        let vpnStatus: BehaviorSubject<NEVPNStatus>
    }

    // Messages accepted by `LandingPageActor`.
    enum Action: AnyMessage {
        /// Will try to open latest stored landing page for the current session if VPN is connected.
        case showLandingPage
        /// Resets the shown landing page for current session flag.
        case reset
    }

    /// Result messages accepted by `LandingPageActor`.
    fileprivate enum Result: AnyMessage {
        /// Opens URL if VPN is connected.
        case openURL(RestrictedURL)
        /// Success status of opening the URL.
        case opened(Bool)
    }

    var context: ActorContext!
    let param: Params
    let disposeBag = DisposeBag()
    var shownLandingPage: Progressive<Bool> = .done(false)

    lazy var receive = behavior { [unowned self] in
        switch $0 {
        case let msg as Action:

            switch msg {
            case .showLandingPage:

                // Emits `.none` if VPN is not connected within 1 second of receiving this message.
                // TODO! VPNStatusBridge shouldn't be hardcoded.

                /// ".NewHomepages" IPC from the network extension often arrives before the VPNStatus has changed to
                /// to the connected state. Therefore, observable below waits some amount of time to make sure VPNStatus
                /// has become connected, before continuing to display the landing page.

                self.param.vpnStatus
                    .falseIfNotTrueWithin(.seconds(1)) {
                        $0 == .connected
                    }
                    .flatMap { vpnConnected -> Single<RestrictedURL?> in
                        guard vpnConnected else {
                            return Single.just(.none)
                        }

                        return modifyLandingPageWithPsicash(psiCash: self.param.psiCash,
                                                            sharedDB: self.param.sharedDB)
                    }
                    .subscribe(onSuccess: {
                        guard let landingPage = $0 else {
                            return
                        }
                        self ! LandingPageActor.Result.openURL(landingPage)
                    })
                    .disposed(by: self.disposeBag)

            case .reset:
                self.shownLandingPage = .done(false)
            }

        case let msg as LandingPageActor.Result:
            switch msg {
            case .openURL(let landingPage):
                guard case .done(false) = self.shownLandingPage else {
                    return .same
                }

                self.shownLandingPage = .inProgress
                openRestrictedURL(landingPage, self.param.vpnManager, replyTo: self)

            case .opened(let success):
                self.shownLandingPage = .done(success)
            }

        default: return .unhandled($0)
        }
        return .same
    }

    required init(_ param: Params) {
        self.param = param
    }

}

/// Opens `RestrictedURL` on the main thread, and sends success result to `replyTo` actor.
fileprivate func openRestrictedURL(_ landingPage: RestrictedURL,
                                   _ vpnManager: VPNManager,
                                   replyTo: ActorRef) {
    // FIX: Let the actor mesage loop run on the main thread.
    DispatchQueue.main.async {
        /// Due to memory pressure, the network extension is at high risk of jetsamming before the landing page can be opened.
        /// Tunnel status should be assessed directly (not through observables that might introduce some latency),
        /// before opening the landing page.
        guard let landingPage = landingPage.getURL(vpnManager.tunnelProviderStatus) else {
                return
        }

        UIApplication.shared.open(landingPage) { success in
            replyTo ! LandingPageActor.Result.opened(success)
        }
    }
}

/// Asks `PsiCashActor` if available to modify the landing page url with PsiCash.
/// If VPN is not connected within 1 second of subscribing to the returned observable, `.none` is emitted.
/// - Returns: Observable that emits `RestrictedURL?` and then completes.
fileprivate func modifyLandingPageWithPsicash(psiCash: Observable<PsiCashActorPublisher?>,
                                              sharedDB: PsiphonDataSharedDB)
    -> Single<RestrictedURL?> {

        psiCash
            .currentState()
            .flatMap { (psiCash: PsiCashActorPublisher?) -> Single<ActorRef?> in
                guard let psiCashActorPublisher = psiCash else {
                    return Single.just(.none)
                }

                return psiCashActorPublisher.publisher
                    .falseIfNotTrueWithin(.seconds(3)) {
                        $0.lib.authPackage.hasEarnerToken
                    }
                    .map { $0 ? psiCashActorPublisher.actor : .none }

            }
        .flatMap { result -> Single<RestrictedURL?> in

            guard let unmodifiedLandingPage = randomLandingPage(sharedDB) else {
                return Single.just(.none)
            }

            switch result {
            case .none:
                // If user has no PsiCash earner token, return the unmodified landing page.
                return Single.just(unmodifiedLandingPage)

            case .some(let psiCashActor):
                return Single.just(unmodifiedLandingPage)
                    .mapAsync(as: RestrictedURL?.self) {
                        psiCashActor ?! PsiCashActor.Action.modifyLandingPage($0)
                    }
            }
    }

}

/// Returns a random landing page from set of stored pages in `sharedDB`.
/// - Returns: landing page, or `.none` if no landing pages stored.
fileprivate func randomLandingPage(_ sharedDB: PsiphonDataSharedDB) -> RestrictedURL? {
    guard let landingPages = sharedDB.getHomepages(), landingPages.count > 0 else {
            return .none
    }
    return RestrictedURL(landingPages.randomElement()!.url)
}
