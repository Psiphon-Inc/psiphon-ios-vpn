/*
* Copyright (c) 2020, Psiphon Inc.
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
import NetworkExtension
import PsiApi

struct ProviderManagerLoadState<T: TunnelProviderManager>: Equatable {
    
    enum TPMError: HashableError {
        case failedRemovingConfigs([NEVPNError])
        case failedConfigLoadSave(NEVPNError)
    }
    
    enum LoadState: Equatable {
        case nonLoaded
        case noneStored
        case loaded(T)
        case error(ErrorEvent<TPMError>)
    }
    
    private(set) var value: LoadState = .nonLoaded
    
}

/// Psiphon tunnel is either in a connecting or connected state when the tunnel provider
/// is not in a zombie state.
enum PsiphonTunnelState: Equatable {
    case connected
    case connecting
    case networkNotReachable
}

enum PendingTunnelTransition: Equatable {
    case restart
}

enum TunnelStartStopIntentReason: Equatable, FeedbackDescription {
    case userInitiated
    case providerIsZombie
    case vpnConfigValidationFailed
}

enum TunnelStartStopIntent: Equatable, FeedbackDescription {
    case start(transition: PendingTunnelTransition?)
    case stop
}

struct VPNStatusWithIntent: Equatable {
    let status: TunnelProviderVPNStatus
    let intent: TunnelStartStopIntent?
    
    var willReconnect: Bool {
        switch self.intent {
        case .some(.start(transition: .none)): return true
        default: return false
        }
    }
}

extension ProviderManagerLoadState {
    
    var connectionStatus: TunnelProviderVPNStatus {
        guard case let .loaded(tpm) = self.value else {
            return .invalid
        }
        return tpm.connectionStatus
    }
    
    var vpnConfigurationInstalled: Bool {
        switch self.value {
        case .nonLoaded:
            fatalError("VPN Config not loaded")
        case .loaded(_):
            return true
        case .noneStored, .error(_):
            return false
        }
    }
    
    /// Updates `ProviderManagerLoadState`.
    /// - Returns: Tuple `(updateEffects: , vpnStatusInvalid:),`. where `updateEffects`
    /// is set of effects from state update. `vpnStatusInvalid` is true if tunnel provider manager has been removed
    /// and VPN status should be considered same as `NEVPNStatusInvalid`.
    mutating func updateState(
        configUpdateResult: Result<(T, VPNConnectionObserver<T>)?, ErrorEvent<TPMError>>,
        feedbackLogger: FeedbackLogger
    ) -> (updateEffects: [Effect<Never>], vpnStatusInvalid: Bool) {
        let previousValue = self.value
        switch configUpdateResult {
        case .success(.none):
            self.value = .noneStored
            return (updateEffects: [], vpnStatusInvalid: true)
            
        case .success(let .some((tpm, connectionObserver))):
            self.value = .loaded(tpm)
            if case .loaded(let previousTpm) = previousValue, previousTpm == tpm {
                return (updateEffects: [], vpnStatusInvalid: false)
            } else {
                let observeEffect = Effect<Never>.fireAndForget { [tpm] in
                    tpm.observeConnectionStatus(observer: connectionObserver)
                }
                return (updateEffects: [ observeEffect ], vpnStatusInvalid: false)
            }
            
        case .failure(let errorEvent):
            self.value = .error(errorEvent)
            let feedbackEffect = feedbackLogger.log(
                .error, tag: "ProviderManagerStateUpdate", errorEvent)
            return (updateEffects: [ feedbackEffect ], vpnStatusInvalid: true)
        }
    }
    
}
