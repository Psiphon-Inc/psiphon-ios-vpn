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
import ReactiveSwift
import NetworkExtension

/// Note on terminology:
/// - Psiphon tunnel is to the tunnel created in the Network Extension process.
/// - Tunnel provider referes to the network extension.
/// - Tunnel provider manager is the `NETunnelProivderManager` object that is used to manage the tunnel provider.

fileprivate let vpnConfigLoadTag = LogTag("VPNConfigLoad")
fileprivate let vpnProviderSyncTag = LogTag("VPNProviderSync")
fileprivate let vpnStartTag = LogTag("VPNStart")

/// `VPNStatus` encodes more state such `.restarting` in additions to states defined in `TunnelProviderVPNStatus`
/// (i.e. `NEVPNStatus`).
/// `VPNStatus` generally refers to state that the container is more interested in, which is more than just the connection status
/// of the tunnel provider.
@objc enum VPNStatus: Int {
    /// VPNStatusInvalid The VPN is not configured or unexpected vpn state.
    case invalid = 0
    /// VPNStatusDisconnected No network extension process is running
    /// (When restarting VPNManager status will be VPNStatusRestarting).
    case disconnected = 1
    /// VPNStatusConnecting Network extension process is running but is the VPN is not connected yet.
    /// This state either signified that the tunnel network extension is in a zombie state
    /// or that the Psiphon tunnel has already started (Psiphon tunnel itself could be in connecting or connected state).
    case connecting = 2
    /// VPNStatusConnected Network extension process is running and the tunnel is connected.
    case connected = 3
    /// VPNStatusReasserting Network extension process is running, and the tunnel is reconnecting or has already connected.
    case reasserting = 4
    /// VPNStatusDisconnecting The tunnel and the network extension process are being stopped.
    case disconnecting = 5
    /// VPNStatusRestarting Stopping previous network extension process, and starting a new one.
    case restarting = 6
}

extension VPNStatus: Equatable {
    
    /// `providerNotStopped` value represents whether the tunnel provider process is running, and
    /// is not stopped or in the process of getting stopped.
    /// - Note: A tunnel provider that is running can also be in a zombie state.
    var providerNotStopped: Bool {
        switch self {
        case .invalid, .disconnected, .disconnecting:
            return false
        case .connecting, .connected, .reasserting, .restarting:
            return true
        @unknown default:
            fatalError("unknown NEVPNStatus '\(self.rawValue)'")
        }
    }
    
}

extension TunnelProviderVPNStatus {
    
    func mapToVPNStatus() -> VPNStatus {
        switch self {
        case .invalid: return .invalid
        case .disconnected: return .disconnected
        case .connecting: return .connecting
        case .connected: return .connected
        case .reasserting: return .reasserting
        case .disconnecting: return .disconnecting
        @unknown default:
            fatalError("unknown NEVPNStatus value '\(self.rawValue)'")
        }
    }
    
}

// MARK: -

typealias VPNState<T: TunnelProviderManager> =
    SerialEffectState<VPNProviderManagerState<T>, VPNProviderManagerStateAction<T>>

typealias VPNStateAction<T: TunnelProviderManager> =
    SerialEffectAction<VPNProviderManagerStateAction<T>>

func makeVpnStateReducer<T: TunnelProviderManager>()
    -> Reducer<VPNState<T>, VPNStateAction<T>, VPNReducerEnvironment<T>> {
        makeSerialEffectReducer(vpnProviderManagerStateReducer)
}

enum PendingTunnelTransition: Equatable {
    case restart
}

enum TunnelStartStopIntent: Equatable {
    case start(transition: PendingTunnelTransition?)
    case stop
}

extension TunnelStartStopIntent {
    
    static func initializeIntentGiven(
        _ reason: TunnelProviderSyncReason, _ syncedState: TunnelProviderSyncedState
    ) -> Self {
        guard case .appLaunched = reason else {
            fatalError("should only initialize TunnelStateIntent after app is initially launched")
        }
        switch syncedState {
        case .zombie:
            // Tunnel provider has been in zombie state before app launch,
            // therefore default tunnelIntent state is set to `.stop`.
            return .stop
        case .active(_):
            return .start(transition: .none)
        case .inactive:
            return .stop
        case .unknown(_):
            return .stop
        }
    }
    
}

/// `TunnelProviderStartStopAction` represents start/stop actions for tunnel provider.
enum TunnelProviderStartStopAction: Int {
    case startPsiphonTunnel
    case stopVPN
}

/// Psiphon tunnel is either in a connecting or connected state when the tunnel provider
/// is not in a zombie state.
enum PsiphonTunnelState: Equatable {
    case connected
    case connecting
    case networkNotReachable
}

/// Represents state of the tunnel provider after sync.
/// - Note: State sync is perfomed through sending `EXTENSION_QUERY_TUNNEL_PROVIDER_STATE` to the provider.
enum TunnelProviderSyncedState: Equatable {
    
    enum SyncError: HashableError {
        case neVPNError(NEVPNError)
        case timedout(TimeInterval)
        case responseParseError(String)
    }
    
    /// Psiphon tunnel is not connected when the tunnel provider is in zombie state.
    case zombie
    /// Represents state where tunnel provider is not in zombie state.
    case active(PsiphonTunnelState)
    /// Tunnel provider process is not running
    case inactive
    /// Tunnel provider state is unknown either due to some error in syncing state or before any state sync is perfomed.
    case unknown(ErrorEvent<SyncError>?)
}

typealias ConfigUpdatedResult<T: TunnelProviderManager> =
    Result<T?, ErrorEvent<ProviderManagerLoadState<T>.TPMError>>

enum TPMEffectResultWrapper<T: TunnelProviderManager>: Equatable {
    case configUpdated(ConfigUpdatedResult<T>)
    case syncedStateWithProvider(syncReason: TunnelProviderSyncReason, TunnelProviderSyncedState)
    case startTunnelResult(Result<Unit, ErrorEvent<NEVPNError>>)
    case stopTunnelResult(Unit)
}

@objc enum TunnelProviderSyncReason: Int, Equatable {
    case appLaunched
    case appEnteredForeground
    case providerNotificationPsiphonTunnelConnected
}

enum VPNExternalAction: Equatable {
    case appLaunched
    case syncWithProvider(reason: TunnelProviderSyncReason)
    case reinstallVPNConfig
    case tunnelStateIntent(TunnelStartStopIntent)
}

enum VPNProviderManagerStateAction<T: TunnelProviderManager>: Equatable {
    case tpmEffectResultWrapper(TPMEffectResultWrapper<T>)
    case vpnStatusChanged(TunnelProviderVPNStatus)
    case startPsiphonTunnel
    case stopVPN
    case external(VPNExternalAction)
}

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
    
    private(set) var value: LoadState
    
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
    
    init() {
        self.value = .nonLoaded
    }
    
    func providerManagerForTunnelStart() -> Effect<T> {
        switch self.value {
        case .nonLoaded:
            fatalError()
        case .noneStored, .error(_):
            return Effect(value: T.make())
        case .loaded(let tpm):
            return Effect(value: tpm)
        }
    }
    
    mutating func updateState(
        configUpdateResult: Result<(T, VPNConnectionObserver<T>)?, ErrorEvent<TPMError>>
    ) -> [Effect<Never>] {
        let previousValue = self.value
        switch configUpdateResult {
        case .success(.none):
            self.value = .noneStored
            return []
            
        case .success(let .some((tpm, connectionObserver))):
            self.value = .loaded(tpm)
            guard case .loaded(let previousTpm) = previousValue, previousTpm == tpm else {
                return [
                    .fireAndForget { [tpm] in
                        tpm.observeConnectionStatus(observer: connectionObserver)
                    }
                ]
            }
            return []
            
        case .failure(let errorEvent):
            self.value = .error(errorEvent)
            return [ feedbackLog(.error, tag: "ProviderManagerStateUpdate", errorEvent) ]
        }
    }
    
}

typealias VPNStartStopStateType =
    PendingValue<TunnelProviderStartStopAction,
    Result<TunnelProviderStartStopAction, ErrorEvent<NEVPNError>>>?

struct VPNProviderManagerState<T: TunnelProviderManager>: Equatable {
    var tunnelIntent: TunnelStartStopIntent?
    var loadState: ProviderManagerLoadState<T>
    var providerVPNStatus: TunnelProviderVPNStatus
    var startStopState: VPNStartStopStateType
    var providerSyncResult: Pending<ErrorEvent<TunnelProviderSyncedState.SyncError>?>
}

extension VPNProviderManagerState {
    
    var noPendingProviderStartStopAction: Bool {
        switch startStopState {
        case .none, .completed(_): return true
        case .pending(_): return false
        }
    }
    
    var vpnStatus: VPNStatus {
        if case .start(.restart) = tunnelIntent {
            return .restarting
        } else {
            return providerVPNStatus.mapToVPNStatus()
        }
    }
    
    init() {
        self.tunnelIntent = .none
        self.loadState = .init()
        self.providerVPNStatus = .invalid
        self.startStopState = .none
        self.providerSyncResult = .completed(.none)
    }
    
}

typealias VPNReducerEnvironment<T: TunnelProviderManager> = (
    sharedDB: PsiphonDataSharedDB,
    vpnStartCondition: () -> Bool,
    vpnConnectionObserver: VPNConnectionObserver<T>
)

fileprivate func vpnProviderManagerStateReducer<T: TunnelProviderManager>(
    state: inout VPNProviderManagerState<T>, action: VPNProviderManagerStateAction<T>,
    environment: VPNReducerEnvironment<T>
) -> [Effect<VPNProviderManagerStateAction<T>>] {
    switch action {
    case .tpmEffectResultWrapper(let tunnelProviderAction):
        return tunnelProviderReducer(state: &state, action: tunnelProviderAction,
                                     environment: environment)
        
    case .vpnStatusChanged(let vpnStatus):
        state.providerVPNStatus = vpnStatus
        
        // Resets tunnelIntent transition flag if previously was `.restart`.
        // Discussion:
        // The flag is reset at the disconnecting state change, since this is a clear
        // signal that the provider has started transitioning (being stopped and started again).
        //
        if case .disconnecting = vpnStatus, case .start(transition: .restart) = state.tunnelIntent {
            state.tunnelIntent = .start(transition: .none)
        }
        
        // Sends startPsiphonTunnel message if tunnelIntent is start, and
        // the tunnel has disconnected.
        if case .start(transition: _) = state.tunnelIntent, case .disconnected = vpnStatus {
            return [ Effect(value: .startPsiphonTunnel) ]
        } else {
            return []
        }
          
    case .startPsiphonTunnel:
        return startPsiphonTunnelReducer(state: &state, environment: environment)
        
    case .stopVPN:
        guard state.noPendingProviderStartStopAction else {
            fatalError("""
                cannot stopVPN since there is pending action \
                '\(String(describing: state.startStopState))'
                """)
        }
        
        guard case .loaded(let tpm) = state.loadState.value,
            tpm.connectionStatus.providerNotStopped else {
                return []
        }
        
        state.startStopState = .pending(.stopVPN)
        
        return [
            updateConfig(tpm, for: .stopVPN)
                .flatMap(.latest, saveAndLoadConfig)
            .flatMap(.latest) { result -> Effect<TPMEffectResultWrapper<T>> in
                switch result {
                case .success(let tpm):
                    return stopVPN(tpm)
                        .map { .stopTunnelResult(.unit) }
                        .prefix(value: .configUpdated(.success(tpm)))
                case .failure(let errorEvent):
                    return Effect(value:
                        .configUpdated(.failure(errorEvent.map { .failedConfigLoadSave($0) }))
                    )
                }
            }.map {
                .tpmEffectResultWrapper($0)
            }
        ]
        
    case .external(let externalAction):
        switch externalAction {
        case .appLaunched:
            // Loads current VPN configuration from VPN preferences.
            // After VPN configuration is loaded, `.syncWithProvider` action is sent.
            
            guard case .nonLoaded = state.loadState.value else {
                fatalError()
            }
            state.providerSyncResult = .pending
            return [
                loadAllConfigs().map { .tpmEffectResultWrapper(.configUpdated($0)) },
                Effect(value: .external(.syncWithProvider(reason: .appLaunched)))
            ]
            
        case .syncWithProvider(reason: let reason):
            guard case .loaded(let tpm) = state.loadState.value else {
                state.providerSyncResult = .completed(.none)
                return []
            }
            
            switch reason {
            case .appLaunched:
                // At app launch, `state.providerSyncResult` defaults to `.pending`.
                guard case .pending = state.providerSyncResult else {
                    fatalError()
                }
                return [
                    syncStateWithProvider(syncReason: reason, tpm)
                        .map { .tpmEffectResultWrapper($0) }
                ]
                
            case .appEnteredForeground:
                guard case .completed(_) = state.providerSyncResult else {
                    fatalError()
                }
                state.providerSyncResult = .pending
                return [
                    loadConfig(tpm).flatMap(.latest) { result -> Effect<TPMEffectResultWrapper<T>> in
                        switch result {
                        case .success(let tpm):
                            return syncStateWithProvider(syncReason: reason, tpm)
                                .prefix(value: .configUpdated(.success(tpm)))
                        case .failure(let errorEvent):
                            return Effect(value:
                                .syncedStateWithProvider(syncReason: reason, .unknown(nil))
                            ).prefix(value: .configUpdated(.failure(errorEvent.map {
                                .failedConfigLoadSave($0)
                            })))
                        }
                    }.map {
                        .tpmEffectResultWrapper($0)
                    }
                ]
                
            case .providerNotificationPsiphonTunnelConnected:
                guard case .completed(_) = state.providerSyncResult else {
                    fatalError()
                }
                state.providerSyncResult = .pending
                return [
                    syncStateWithProvider(syncReason: reason, tpm)
                        .map { .tpmEffectResultWrapper($0) }
                ]
            }
            
        case .reinstallVPNConfig:
            if case let .loaded(tpm) = state.loadState.value {
                // Returned effect calls `stop()` on the tunnel provider manager object first,
                // before remvoing the VPN config.
                return [
                    stopVPN(tpm).flatMap(.latest) {
                        removeFromPreferences(tpm)
                            .flatMap(.latest) { result -> Effect<TPMEffectResultWrapper<T>> in
                                switch result {
                                case .success(()):
                                    return installNewVPNConfig()
                                    
                                case .failure(let errorEvent):
                                    return Effect(value:
                                        .configUpdated(
                                            .failure(errorEvent.map{ .failedRemovingConfigs([$0]) })
                                        )
                                    )
                                }
                        }.map {
                            .tpmEffectResultWrapper($0)
                        }
                    }
                ]
            } else {
                return [ installNewVPNConfig().map { .tpmEffectResultWrapper($0) } ]
            }
            
        case .tunnelStateIntent(let intent):
            if intent == state.tunnelIntent {
                return []
            }
            
            switch intent {
            case .start(transition: .none):
                // Starts Psiphon tunnel.
                state.tunnelIntent = .start(transition: .none)
                return [ Effect(value: .startPsiphonTunnel) ]
                
            case .start(transition: .restart):
                // Restarts tunnel provider if not stopped.
                guard case let .loaded(tpm) = state.loadState.value,
                    tpm.connectionStatus.providerNotStopped else {
                        return []
                }
                state.tunnelIntent = .start(transition: .restart)
                return [ Effect(value: .stopVPN) ]
                
            case .stop:
                // Stops tunnel provider.
                state.tunnelIntent = .stop
                return [ Effect(value: .stopVPN) ]
            }
        }
    }
}

fileprivate func tunnelProviderReducer<T: TunnelProviderManager>(
    state: inout VPNProviderManagerState<T>, action: TPMEffectResultWrapper<T>,
    environment: VPNReducerEnvironment<T>
) -> [Effect<VPNProviderManagerStateAction<T>>] {
    switch action {
    case .configUpdated(let result):
        let effects = state.loadState.updateState(
            configUpdateResult: wrapVPNObserverWithTPMResult(
                result,
                environment.vpnConnectionObserver
            )
        )
        return effects.map { $0.mapNever() }
        
    case let .syncedStateWithProvider(syncReason: reason, syncedState):
        guard case .pending = state.providerSyncResult else {
            fatalError()
        }
        guard case let .loaded(tpm) = state.loadState.value else {
            fatalError()
        }
        
        // Updates `state.providerSyncResult` value.
        if case .unknown(let syncErrorEvent) = syncedState {
            state.providerSyncResult = .completed(syncErrorEvent)
        } else {
            state.providerSyncResult = .completed(.none)
        }
        
        // Initialize tunnel intent value given none was previously set.
        switch (reason: reason, currentIntent:state.tunnelIntent, syncedState: syncedState) {
        case (reason: .appLaunched, currentIntent: .none, syncedState: _):
            // Initializes tunnel intent when app is first launched
            state.tunnelIntent = .initializeIntentGiven(reason, syncedState)
        case (reason: _, currentIntent: .stop, syncedState: .active(_)):
            // Updates the tunnel intent to `.start` if the tunnel provider was
            // started from system settings.
            state.tunnelIntent = .start(transition: .none)
        default: break
        }
        
        switch syncedState {
        case .zombie:
            return [
                Effect(value: .stopVPN),
                feedbackLog(.info, tag: vpnProviderSyncTag, "zombie provider").mapNever()
            ]
            
        case .active(.connected):
            guard case .start(transition: .none) = state.tunnelIntent else {
                fatalError()
            }
            guard tpm.verifyConfig(forExpectedType: .startVPN) else {
                // Failed to verify VPN config values.
                // To update the config, tunnel is restarted.
                return [
                    Effect(value: .external(.tunnelStateIntent(.start(transition: .restart))))
                ]
            }
            
            // Sends start vpn notification to the tunnel provider
            // if vpnStartCondition passes.
            guard state.loadState.connectionStatus == .connecting,
                environment.vpnStartCondition() else {
                    return []
            }
            return [ notifyStartVPN().mapNever() ]
            
        case .unknown(let errorEvent):
            guard let errorEvent = errorEvent else {
                fatalError("expected non-nil error after provider state sync")
            }
            
            // Resets tunnel intent, since provider status could not be determined.
            state.tunnelIntent = .none
            
            return [
                Effect(value: .stopVPN),
                feedbackLog(.info, tag: vpnProviderSyncTag, errorEvent).mapNever()
            ]
            
        default:
            return []
        }
        
    case .startTunnelResult(let result):
        guard case .pending(.startPsiphonTunnel) = state.startStopState else {
            fatalError()
        }
        switch result {
        case .success(.unit):
            state.startStopState = .completed(.success(.startPsiphonTunnel))
            return []
        case .failure(let errorEvent):
            state.startStopState = .completed(.failure(errorEvent))
            
            // Resets tunnel intent, since desired tunnel start state could not be achieved.
            state.tunnelIntent = .none
            
            return [ feedbackLog(.error, tag: vpnStartTag, errorEvent).mapNever() ]
        }
        
    case .stopTunnelResult(.unit):
        guard case .pending(.stopVPN) = state.startStopState else {
            fatalError()
        }
        state.startStopState = .completed(.success(.stopVPN))
        return []
    }
}

fileprivate func startPsiphonTunnelReducer<T: TunnelProviderManager>(
    state: inout VPNProviderManagerState<T>, environment: VPNReducerEnvironment<T>
) -> [Effect<VPNProviderManagerStateAction<T>>] {
    
    // No-op if there is any pending provider action.
    guard state.noPendingProviderStartStopAction else {
        fatalError("""
            cannot startPsiphonTunnel since there is pending action \
            '\(String(describing: state.startStopState))'
            """)
    }
    
    // No-op if the tunnel provider is already active.
    if state.loadState.connectionStatus.providerNotStopped {
        return []
    }
    
    state.startStopState = .pending(.startPsiphonTunnel)
    
    let tpmDeffered: Effect<T> = state.loadState.providerManagerForTunnelStart()
    
    // Options passed to tunnel provider start handler function.
    let startOptions = [EXTENSION_OPTION_START_FROM_CONTAINER: EXTENSION_OPTION_TRUE]
    
    return [
        .fireAndForget {
            environment.sharedDB.setContainerTunnelStartTime(Date())
        },
        tpmDeffered.flatMap(.latest) {
            updateConfig($0, for: .startVPN)
        }
        .flatMap(.latest, saveAndLoadConfig)
        .flatMap(.latest) { (saveLoadConfigResult: Result<T, ErrorEvent<NEVPNError>>)
            -> Effect<TPMEffectResultWrapper<T>> in
            switch saveLoadConfigResult {
            case .success(let tpm):
                // Starts the tunnel and then saves the updated config from tunnel start.
                return startPsiphonTunnel(tpm, options: startOptions)
                    .flatMap(.latest) { startResult -> Effect<TPMEffectResultWrapper<T>> in
                        switch startResult {
                        case .success(let tpm):
                            return saveAndLoadConfig(tpm)
                                .map { .configUpdated(.fromConfigSaveAndLoad($0)) }
                            .prefix(value:
                                .startTunnelResult(startResult.dropSuccessValue().mapToUnit())
                            )
                        case .failure(_):
                            return Effect(value:
                                .startTunnelResult(startResult.dropSuccessValue().mapToUnit()))
                                .prefix(value: .configUpdated(.success(tpm)))
                        }
                    }
            case .failure(let errorEvent):
                return Effect(value: .startTunnelResult(.failure(errorEvent)))
                    .prefix(value:
                    .configUpdated(.failure(errorEvent.map { .failedConfigLoadSave($0) }))
                )
            }
        }.map {
            .tpmEffectResultWrapper($0)
        }
    ]
}

// MARK: Utility functions

extension ConfigUpdatedResult {
    
    fileprivate static func fromConfigSaveAndLoad<T: TunnelProviderManager>(
        _ result: Result<T, ErrorEvent<NEVPNError>>
    ) -> Result<T?, ErrorEvent<ProviderManagerLoadState<T>.TPMError>> {
        result.map { .some($0) }
            .mapError { neVPNErrorEvent in
                neVPNErrorEvent.map { .failedConfigLoadSave($0) }
        }
    }
    
}

fileprivate func wrapVPNObserverWithTPMResult<T: TunnelProviderManager, Failure>(
    _ result: Result<T?, Failure>, _ observer: VPNConnectionObserver<T>
) -> Result<(T, VPNConnectionObserver<T>)?, Failure> {
    result.map { maybeManger -> (T, VPNConnectionObserver<T>)? in
        if let manager = maybeManger {
            return (manager, observer)
        } else {
            return nil
        }
    }
}

// MARK: Effects

fileprivate func notifyStartVPN() -> Effect<Never> {
    .fireAndForget {
        Notifier.sharedInstance().post(NotifierStartVPN)
    }
}

/// Creates a new `TunnelProviderManager` of type `T`, and saves the VPN configuration to device.
fileprivate func installNewVPNConfig<T: TunnelProviderManager>()
    -> Effect<TPMEffectResultWrapper<T>> {
        return Effect(value: T.make()).flatMap(.latest) {
            updateConfig($0, for: .startVPN)
        }
        .flatMap(.latest, saveAndLoadConfig)
        .map { result -> TPMEffectResultWrapper<T> in
            return .configUpdated(.fromConfigSaveAndLoad(result))
        }
}

fileprivate func loadAllConfigs<T: TunnelProviderManager>() -> Effect<ConfigUpdatedResult<T>> {
    loadFromPreferences()
        .flatMap(.latest) { (result: Result<[T], ErrorEvent<NEVPNError>>)
            -> Effect<ConfigUpdatedResult<T>> in
            switch result {
            case .success(let tpms):
                switch tpms.count {
                case 0:
                    // There is no provider to sync with.
                    return Effect(value: .success(nil))
                case 1:
                    return Effect(value: .success(tpms.first!))
                default:
                    // There should only be one confiugation stored in VPN preferences.
                    // Returned effect removes all configuartions in `tpms` from apps
                    // VPN preferences.
                    return Effect(tpms)
                        .flatMap(.merge, removeFromPreferences)
                        .collect()
                        .map { results -> ConfigUpdatedResult<T> in
                            let errors = results.compactMap { $0.projectError()?.error }
                            if errors.count > 0 {
                                return .failure(ErrorEvent(.failedRemovingConfigs(errors)))
                            } else {
                                return .success(nil)
                            }
                    }
                }
            case .failure(let errorEvent):
                return Effect(value: .failure(errorEvent.map { .failedConfigLoadSave($0) }))
            }
    }
}

fileprivate struct ProviderStateQueryResponseValue: Decodable {
    let isZombie: Bool
    let isPsiphonTunnelConnected: Bool
    let isNetworkReachable: Bool
    
    private enum CodingKeys: String, CodingKey {
        case isZombie = "isZombie"
        case isPsiphonTunnelConnected = "isPsiphonTunnelConnected"
        case isNetworkReachable = "isNetworkReachable"
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isZombie = try values.decode(Bool.self, forKey: .isZombie)
        isPsiphonTunnelConnected = try values.decode(Bool.self, forKey: .isPsiphonTunnelConnected)
        isNetworkReachable = try values.decode(Bool.self, forKey: .isNetworkReachable)
    }
    
}

extension TunnelProviderSyncedState.SyncError {
    
    fileprivate static func make(fromSendError sendError: ProviderMessageSendError) -> Self? {
        switch sendError {
        case .providerNotActive:
            return nil
        case .timedout(let interval):
            return .timedout(interval)
        case .neVPNError(let neVPNError):
            return .neVPNError(neVPNError)
        case .parseError(let string):
            return .responseParseError(string)
        }
    }
    
}

extension TunnelProviderSyncedState {
    
    fileprivate static func make(fromQueryResult result: ProviderStateQueryResult) -> Self {
        switch result {
        case let .success(response):
            let responseValues = (zombie: response.isZombie,
                                  connected: response.isPsiphonTunnelConnected,
                                  reachable: response.isNetworkReachable)
            switch responseValues {
            case (zombie: true, connected: false, reachable: _):
                return .zombie
            case (zombie: false, connected: false, reachable: false):
                return .active(.networkNotReachable)
            case (zombie: false, connected: false, reachable: true):
                return .active(.connecting)
            case (zombie: false, connected: true, reachable: true):
                return .active(.connected)
            default:
                fatalError("unexpected tunnel provider response '\(response)'")
            }
            
        case let .failure(errorEvent):
            switch errorEvent.error {
            case .providerNotActive:
                return .inactive
            case .timedout, .neVPNError, .parseError:
                return .unknown(errorEvent.map { sendError -> SyncError in
                    guard let syncError = SyncError.make(fromSendError: sendError) else {
                        fatalError("""
                            failed to map '\(String(describing: errorEvent))' to 'SyncError'
                            """)
                    }
                    return syncError
                })
            }
        }
    }
    
}

fileprivate func syncStateWithProvider<T: TunnelProviderManager>(
    syncReason: TunnelProviderSyncReason,_ tpm: T
) -> Effect<TPMEffectResultWrapper<T>> {
    sendProviderStateQuery(tpm).map { _, queryResult in
        let providerState = TunnelProviderSyncedState.make(fromQueryResult: queryResult)
        return .syncedStateWithProvider(syncReason: syncReason, providerState)
    }
}

// Response result type alias of TunnelProviderManager.sendProviderStateQuery()
fileprivate typealias ProviderStateQueryResult =
    Result<ProviderStateQueryResponseValue, ErrorEvent<ProviderMessageSendError>>

typealias ShouldStopProviderResult<T: TunnelProviderManager> = (
    tpm: T,
    shouldStopProvider: Bool,
    isZombie: Bool,
    error: ErrorEvent<ProviderMessageSendError>?
)

fileprivate func sendProviderStateQuery<T: TunnelProviderManager>(
    _ tpm: T
) -> Effect<(T, ProviderStateQueryResult)> {
    let queryData = EXTENSION_QUERY_TUNNEL_PROVIDER_STATE.data(using: .utf8)!
    let timeoutInterval = VPNHardCodedValues.providerMessageSendTimeout
    
    return sendMessage(toProvider: tpm, data: queryData).map { tpm, result in
        switch result {
        case let .success(responseData):
            do {
                let providerState = try JSONDecoder()
                    .decode(ProviderStateQueryResponseValue.self, from: responseData)
                return (tpm, .success(providerState))
            } catch {
                return (tpm, .failure(ErrorEvent(.parseError(String(describing: error)))))
            }
            
        case .failure(let errorEvent):
            return (tpm, .failure(errorEvent))
        }
    }
    .promoteError(ProviderMessageSendError.self)
    .timeout(after: timeoutInterval,
             raising: ProviderMessageSendError.timedout(timeoutInterval),
             on: QueueScheduler.main)
    .flatMapError { [tpm] error -> Effect<(T, ProviderStateQueryResult)> in
            return Effect(value: (tpm, .failure(ErrorEvent(error))))
    }
    
}
