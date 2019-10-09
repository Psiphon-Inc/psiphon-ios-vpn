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

enum AppActorType: String {
    case psiCash
    case landingPage
    case inAppPurchase
    case subscription
}

protocol ActorBuilder {
    func makeActor<A>(_ parent: ActorRefFactory, _ props: Props<A>, type: AppActorType) -> ActorRef
}

struct DefaultActorBuilder: ActorBuilder {

    func makeActor<A>(_ parent: ActorRefFactory, _ props: Props<A>, type: AppActorType)
        -> ActorRef {
        return parent.spawn(props, name: type.rawValue)
    }

}
