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


/// Bridges VPN status observable to Swift.
@objc class VPNStatusBridge: NSObject {

    @objc static let instance = VPNStatusBridge()

    let status = BehaviorSubject<NEVPNStatus>(value: NEVPNStatus.invalid)

    @objc func next(_ vpnStatus: NEVPNStatus) {
        self.status.onNext(vpnStatus)
    }

}


// MARK: SwiftAppDelegate
@objc class SwiftAppDelegate: NSObject {

    @objc static let instance = SwiftAppDelegate()

    let system = ActorSystem(name: "system")
    let sharedDB = PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER)
    let disposeBag = DisposeBag()

    var vpnManager: VPNManager!
    var appRoot: ActorRef?
    let services = Services()

    /// Spawns app root actor `AppRoot`.
    func makeAppRootActor() -> ActorRef {

        let props = Props(AppRoot.self,
                          param: AppRoot.Params(
                            actorBuilder: DefaultActorBuilder(),
                            sharedDB: self.sharedDB,
                            vpnManager: self.vpnManager,
                            vpnStatus: VPNStatusBridge.instance.status,
                            initServices: self.services),
                          qos: .userInteractive)

        return system.spawn(props, name: "AppRoot")
    }

}

extension SwiftAppDelegate: UIApplicationDelegate {

    @objc func applicationDidFinishLaunching(_ application: UIApplication) {
        self.appRoot = makeAppRootActor()

        self.services.psiCash.currentState().subscribe(onSuccess: {
            $0?.actor ! PsiCashActor.Action.refreshState
        }).disposed(by: self.disposeBag)
    }

    @objc func applicationWillEnterForeground(_ application: UIApplication) {
        self.services.psiCash.currentState().subscribe(onSuccess: {
            $0?.actor ! PsiCashActor.Action.refreshState
        }).disposed(by: self.disposeBag)
    }

}


// MARK: ObjC functions

extension SwiftAppDelegate {

    @objc func setVPNManager(_ vpnManager: VPNManager) {
        self.vpnManager = vpnManager
    }

    @objc func createPsiCashViewController() -> UIViewController {

        // TODO! finish creating PsiCashViewController in Swift
        // Three ways to implement this:
        // 1. Pass in registry actor, and let the view controller `ask` for the
        //    the actor services that it needs.
        // 2. Have registry actor expose a Observable<HashMap> of all the services it has as a publisher.
        //    This observable can be create by SwiftAppDelegate.
        // 3. Pass in the Observable/Context container for the actors to `Register` actor,
        //    and hold references to them the ViewControllers.
        //    Like 2. these can be create in SwiftAppDelegate.
        //
        // 3 is chosen.
        return PsiCashViewController(psiCash: self.services.psiCash)
    }

    @objc func getCustomRewardData(_ callback: @escaping (String?) -> Void) {
        //  TODO! fix this
//        guard let psiCash = psiCash else {
//            callback(nil)
//            return
//        }
//
//        (psiCash.service ?! PsiCashService.Action.rewardedVideoCustomData).then {
//            guard let data = $0 as? String else {
//                callback(nil)
//                return
//            }
//            callback(data)
//            }.catch { _ in
//                callback(nil)
//        }
    }

}

// MARK: LandingPageService interface
extension SwiftAppDelegate {

    @objc func resetLandingPage() {
        // TODO! fix this
//        landingPageService? ! LandingPageService.Action.reset
    }

    @objc func showLandingPage() {
        // TODO! fix this
//        landingPageService? ! LandingPageService.Action.showLandingPage
    }

}

