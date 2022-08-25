/*
 * Copyright (c) 2022, Psiphon Inc.
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
import PsiApi
import AppStoreIAP
import PsiCashClient

enum PurchaseRequiredPrompt {
    
    /// Predicate for whether a required purchase prompt can be presented if
    /// `"ShowPurchaseRequiredPrompt": true` value was received from Psiphon server.
    static func canPresent(
        dateCompare: DateCompare,
        psiCashState: PsiCashState,
        subscriptionStatus: SubscriptionStatus,
        tunnelConnectedStatus: TunnelConnectedStatus
    ) -> Bool {
        let speedBoosted = psiCashState.activeSpeedBoost(dateCompare) != nil
        return !speedBoosted &&
               !subscriptionStatus.subscribed &&
               (tunnelConnectedStatus == .connected || tunnelConnectedStatus == .connecting)
    }
    
}

enum DisallowedTrafficPrompt {
    
    /// Predicate for whether a disallowed-traffic prompt can be presented if
    /// `"disallowed-traffic"` server alert was received from Psiphon server.
    static func canPresent(
        dateCompare: DateCompare,
        psiCashState: PsiCashState,
        subscriptionStatus: SubscriptionStatus,
        tunnelConnectedStatus: TunnelConnectedStatus
    ) -> Bool {
        let speedBoosted = psiCashState.activeSpeedBoost(dateCompare) != nil
        return !speedBoosted &&
               !subscriptionStatus.subscribed &&
               (tunnelConnectedStatus == .connected || tunnelConnectedStatus == .connecting)
    }
    
}

// TODO: Move NEEvents data to a shared database with the network extension.
enum NEEventType: Equatable {
    case disallowedTraffic
    case requiredPurchasePrompt
}

extension NEEventType {
    
    func unhandledEventSeq(_ sharedDB: PsiphonDataSharedDB) -> Int? {
        
        let lastHandledSeq: Int
        let lastWrittenSeq: Int
        
        switch self {
        case .disallowedTraffic:
            lastHandledSeq = sharedDB.getContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum()
            lastWrittenSeq = sharedDB.getDisallowedTrafficAlertWriteSequenceNum()
            
        case .requiredPurchasePrompt:
            lastHandledSeq = sharedDB.getContainerPurchaseRequiredReadAtLeastUpToSequenceNum()
            lastWrittenSeq = sharedDB.getPurchaseRequiredPromptWriteSequenceNum()
        }
        
        if lastWrittenSeq > lastHandledSeq {
            return lastWrittenSeq
        } else {
            return nil
        }
        
    }
    
    func setEventHandled(_ sharedDB: PsiphonDataSharedDB, _ seq: Int) {
        switch self {
        case .disallowedTraffic:
            sharedDB.setContainerDisallowedTrafficAlertReadAtLeastUpToSequenceNum(seq)
        case .requiredPurchasePrompt:
            sharedDB.setContainerPurchaseRequiredReadAtLeastUpToSequenceNum(seq)
        }
    }
    
}
