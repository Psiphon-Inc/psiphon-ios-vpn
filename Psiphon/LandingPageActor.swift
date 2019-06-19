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


typealias RestrictedURL = PredicatedValue<URL, Environment>

final class LandingPageActor: Actor, TypedInput {
    typealias InputType = Action

    // Messages accepted by `LandingPageActor`.
    enum Action: AnyMessage {
        /// Will try to open latest stored landing page for the current session if VPN is connected.
        case open(RestrictedURL)
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
    private let (lifetime, token) = Lifetime.make()
    private var shownLandingPage: Progressive<Bool> = .done(false)
    
    lazy var receive = behavior { [unowned self] in
        switch $0 {
        case let msg as Action:
            switch msg {
            case .open(let restrictedURL):
                /// ".NewHomepages" IPC from the network extension often arrives before the VPNStatus has changed to
                /// to the connected state. Therefore, observable below waits some amount of time to make sure VPNStatus
                /// has become connected, before continuing to display the landing page.

                // Emits `false` if VPN is not connected within 1 second of receiving this message.
                // TODO: double-check lifetime
                Current.vpnStatus.signalProducer.take(during: self.lifetime)
                    .map { $0 == .connected }
                    .falseIfNotTrue(within: .seconds(1))
                    .filter { $0 }
                    .startWithValues { _ in self ! Result.openURL(restrictedURL) }
                return .same

            case .reset:
                self.shownLandingPage = .done(false)
                return . same
            }

        case let msg as LandingPageActor.Result:
            switch msg {
            case .openURL(let landingPage):
                guard case .done(false) = self.shownLandingPage else {
                    return .same
                }

                self.shownLandingPage = .inProgress
                if !Current.debugging.disableLandingPage {
                    openRestrictedURL(landingPage, Current.vpnManager, replyTo: self)
                }
                return .same

            case .opened(let success):
                self.shownLandingPage = .done(success)
                return .same
            }

        default: return .unhandled
        }
    }

    required init(_ param: ()) {}

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
        guard let landingPage = landingPage.getValue(Current) else {
                return
        }

        UIApplication.shared.open(landingPage) { success in
            replyTo ! LandingPageActor.Result.opened(success)
        }
    }
}
