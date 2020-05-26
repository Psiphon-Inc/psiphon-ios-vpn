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
import Utilities


public enum TunnelConnectedStatus {
    case connected
    case connecting
    case disconnecting
    case notConnected
}

/// Connection status of the tunnel provider.
public typealias TunnelProviderVPNStatus = NEVPNStatus

extension TunnelProviderVPNStatus {
    
    /// `providerNotStopped` value represents whether the tunnel provider process is running, and
    /// is not stopped or in the process of getting stopped.
    /// - Note: A tunnel provider that is running can also be in a zombie state.
    public var providerNotStopped: Bool {
        switch self {
        case .invalid, .disconnected, .disconnecting:
            return false
        case .connecting, .connected, .reasserting:
            return true
        @unknown default:
            fatalError("unknown NEVPNStatus value '\(self.rawValue)'")
        }
    }
    
    public var tunneled: TunnelConnectedStatus {
        if Debugging.ignoreTunneledChecks {
            return .connected
        }
        switch self {
        case .invalid, .disconnected:
            return .notConnected
        case .connecting, .reasserting:
            return .connecting
        case .connected:
            return .connected
        case .disconnecting:
            return .disconnecting
        @unknown default:
            fatalError("Unknown NEVPNStatus '\(self.rawValue)'")
        }
    }
    
}

extension NEVPNError {
    
    public var configurationReadWriteFailedPermissionDenied: Bool {
        return self.code == .configurationReadWriteFailed &&
            self.localizedDescription == "permission denied"
    }
    
}

public enum TunnelProviderManagerUpdateType {
    case startVPN
    case stopVPN
}

public enum ProviderMessageSendError: HashableError {
    case providerNotActive
    case timedout(TimeInterval)
    case neVPNError(NEVPNError)
    case parseError(String)
}

public class VPNConnectionObserver<T: TunnelProviderManager>: StoreDelegate<TunnelProviderVPNStatus> {
    func setTunnelProviderManager(_ manager: T) {}
}

public final class TunnelConnection: Equatable {
    
    public enum ConnectionResourceStatus: Equatable {
        case resourceReleased
        case connection(TunnelProviderVPNStatus)
    }
    
    public let connectionStatus: () -> ConnectionResourceStatus
    
    public var tunneled: TunnelConnectedStatus {
        switch self.connectionStatus() {
        case .resourceReleased:
            return .notConnected
            
        case .connection(let connectionStatus):
            if Debugging.ignoreTunneledChecks {
                return .connected
            }
            switch connectionStatus {
            case .invalid, .disconnected:
                return .notConnected
            case .connecting, .reasserting:
                return .connecting
            case .connected:
                return .connected
            case .disconnecting:
                return .disconnecting
            @unknown default:
                fatalError("Unknown NEVPNStatus '\(connectionStatus.rawValue)'")
            }
        }
    }
    
    public init(_ connectionStatus: @escaping () -> ConnectionResourceStatus) {
        self.connectionStatus = connectionStatus
    }
    
    public static func == (lhs: TunnelConnection, rhs: TunnelConnection) -> Bool {
        return lhs === rhs
    }
    
}

public protocol TunnelProviderManager: ClassBound, Equatable {

    var connectionStatus: TunnelProviderVPNStatus { get }
    
    var connection: TunnelConnection { get }
    
    static func loadAll(completionHandler: @escaping ([Self]?, NEVPNError?) -> Void)
    
    static func make() -> Self
    
    func save(completionHandler: @escaping (NEVPNError?) -> Void)
    
    func load(completionHandler: @escaping (NEVPNError?) -> Void)
    
    func remove(completionHandler: @escaping (NEVPNError?) -> Void)
    
    func start(options: [String : Any]?) throws
    
    func stop()
    
    func sendProviderMessage(_ messageData: Data, responseHandler: @escaping (Data?) -> Void) throws
    
    func observeConnectionStatus(observer: VPNConnectionObserver<Self>)
    
    func verifyConfig(forExpectedType expectedType: TunnelProviderManagerUpdateType) -> Bool

    func updateConfig(for updateType: TunnelProviderManagerUpdateType)
    
}

/// Wrapper around `NETunnelProviderManager` that adheres to TunnelProviderManager protocol.
public final class PsiphonTPM: TunnelProviderManager {
    
    public var connectionStatus: TunnelProviderVPNStatus {
        wrappedManager.connection.status
    }

    fileprivate let wrappedManager: NETunnelProviderManager
    
    lazy public var connection = TunnelConnection { [weak wrappedManager] in
        guard let tunnelManager = wrappedManager else {
            return .resourceReleased
        }
        return .connection(tunnelManager.connection.status as TunnelProviderVPNStatus)
    }
    
    private init(_ manager: NETunnelProviderManager) {
        self.wrappedManager = manager
    }
    
    private static func VPNError(from maybeError: Error?) -> NEVPNError? {
        if let error = maybeError {
            return NEVPNError(_nsError: error as NSError)
        } else {
            return nil
        }
    }
    
    public static func make() -> PsiphonTPM {
        let providerProtocol = NETunnelProviderProtocol()
        providerProtocol.providerBundleIdentifier = "ca.psiphon.Psiphon.PsiphonVPN"
        providerProtocol.serverAddress = "localhost"
        let instance = PsiphonTPM(NETunnelProviderManager())
        instance.wrappedManager.protocolConfiguration = providerProtocol
        return instance
    }
    
    public static func loadAll(
        completionHandler: @escaping ([PsiphonTPM]?, NEVPNError?) -> Void
    ) {
        return NETunnelProviderManager.loadAllFromPreferences { (maybeManagers, maybeError) in
            completionHandler(maybeManagers?.map(PsiphonTPM.init), Self.VPNError(from: maybeError))
        }
    }
    
    public func save(completionHandler: @escaping (NEVPNError?) -> Void) {
        self.wrappedManager.saveToPreferences { maybeError in
            completionHandler(Self.VPNError(from: maybeError))
        }
    }
    
    public func load(completionHandler: @escaping (NEVPNError?) -> Void) {
        self.wrappedManager.loadFromPreferences { maybeError in
            completionHandler(Self.VPNError(from: maybeError))
        }
    }
    
    /// Ref:
    /// https://developer.apple.com/documentation/networkextension/nevpnmanager/1406202-removefrompreferences
    /// After the configuration is removed from the preferences the NEVPNManager object will still
    /// contain the configuration parameters. Calling `loadFromPreferences(completionHandler:):`
    /// will clear out the configuration parameters from the NEVPNManager object.
    public func remove(completionHandler: @escaping (NEVPNError?) -> Void) {
        self.wrappedManager.removeFromPreferences { maybeError in
            completionHandler(Self.VPNError(from: maybeError))
        }
    }
    
    public func start(options: [String : Any]?) throws {
        let session = self.wrappedManager.connection as! NETunnelProviderSession
        try session.startTunnel(options: options)
        // Enables Connect On Demand only after starting the tunnel.
        // Otherwise, a race condition is created in the network extension
        // between call to `startVPNTunnelWithOptions` and Connect On Demand.
        self.wrappedManager.isOnDemandEnabled = true
        
        if Debugging.disableConnectOnDemand {
            self.wrappedManager.isOnDemandEnabled = false
        }
    }
    
    public func stop() {
        self.wrappedManager.connection.stopVPNTunnel()
    }
    
    public func sendProviderMessage(
        _ messageData: Data, responseHandler: @escaping (Data?) -> Void
    ) throws {
        let session = self.wrappedManager.connection as! NETunnelProviderSession
        try session.sendProviderMessage(messageData, responseHandler: responseHandler)
    }
    
    public func observeConnectionStatus(observer: VPNConnectionObserver<PsiphonTPM>) {
        observer.setTunnelProviderManager(self)
    }
    
    public func verifyConfig(forExpectedType expectedType: TunnelProviderManagerUpdateType) -> Bool {
        switch expectedType {
        case .startVPN:
            guard self.wrappedManager.isEnabled else {
                return false
            }
            guard let _ = NonEmpty(array: self.wrappedManager.onDemandRules) else {
                return false
            }
            // Disables Connect On Demand flag check, if debugging flag is set.
            if !Debugging.disableConnectOnDemand {
                guard self.wrappedManager.isOnDemandEnabled else {
                    return false
                }
            }
            return true
        case .stopVPN:
            guard self.wrappedManager.isEnabled == false else {
                return false
            }
            guard self.wrappedManager.isOnDemandEnabled == false else {
                return false
            }
            return true
        }
    }
    
    public func updateConfig(for updateType: TunnelProviderManagerUpdateType) {
        switch updateType {
        case .startVPN:
            // setEnabled becomes false if the user changes the
            // enabled VPN Configuration from the preferences.
            self.wrappedManager.isEnabled = true
            
            // Adds "always connect" Connect On Demand rule to the configuration.
            if self.wrappedManager.onDemandRules == nil ||
                self.wrappedManager.onDemandRules?.count == 0
            {
                let alwaysConnectRule: NEOnDemandRule = NEOnDemandRuleConnect()
                self.wrappedManager.onDemandRules = [ alwaysConnectRule ]
            }
            
            // Reset Connect On Demand state.
            // To enable Connect On Demand for all, it should be enabled
            // right before startPsiphonTunnel is called on the NETunnelProviderManager object.
            self.wrappedManager.isOnDemandEnabled = false
            
        case .stopVPN:
            self.wrappedManager.isOnDemandEnabled = false
        }
    }
    
    public static func == (
        lhs: PsiphonTPM, rhs: PsiphonTPM
    ) -> Bool {
        lhs.wrappedManager === rhs.wrappedManager
    }
    
}

public func loadFromPreferences<T: TunnelProviderManager>()
    -> Effect<Result<[T], ErrorEvent<NEVPNError>>>
{
    Effect.deferred { fulfilled in
        T.loadAll { (maybeManagers: [T]?, maybeError: Error?) in
                switch (maybeManagers, maybeError) {
                case (nil, nil):
                    fulfilled(.success([]))
                case (.some(let managers), nil):
                    fulfilled(.success(managers))
                case (_ , .some(let error)):
                    fulfilled(.failure(ErrorEvent(NEVPNError(_nsError: error as NSError))))
                }
        }
    }
}

public func updateConfig<T: TunnelProviderManager>(
    _ tpm: T, for updateType: TunnelProviderManagerUpdateType
) -> Effect<T> {
    Effect { () -> T in
        tpm.updateConfig(for: updateType)
        return tpm
    }
}

public enum StartTunnelError: HashableError {
    case neVPNError(NEVPNError)
    case internetNotReachable
}

public func startPsiphonTunnel<T: TunnelProviderManager>(
    _ tpm: T, options: [String: String], internetReachability: InternetReachability
) -> Effect<Result<T, ErrorEvent<StartTunnelError>>> {
            Effect { () -> Result<T, ErrorEvent<StartTunnelError>> in
                guard internetReachability.isCurrentlyReachable else {
                    return .failure(ErrorEvent(.internetNotReachable))
                }
                do {
                    try tpm.start(options: options)
                    return .success(tpm)
                } catch {
                    return .failure(ErrorEvent(.neVPNError(NEVPNError(_nsError: error as NSError))))
                }
            }
}

public func stopVPN<T: TunnelProviderManager>(_ tpm: T) -> Effect<()> {
    Effect { () -> Void in
        tpm.stop()
        return ()
    }
}

public func loadConfig<T: TunnelProviderManager>(_ tpm: T)
    -> Effect<Result<T, ErrorEvent<NEVPNError>>>
{
    Effect.deferred { fulfilled in
        tpm.load { maybeError in
            if let error = maybeError {
                fulfilled(.failure(ErrorEvent(error)))
            } else {
                fulfilled(.success(tpm))
            }
        }
    }
}

public func saveAndLoadConfig<T: TunnelProviderManager>(_ tpm: T)
    -> Effect<Result<T, ErrorEvent<NEVPNError>>>
{
    Effect.deferred { fulfilled in
        tpm.save { maybeError in
            if let error = maybeError {
                fulfilled(.failure(ErrorEvent(error)))
            } else {
                tpm.load { maybeError in
                    if let error = maybeError {
                        fulfilled(.failure(ErrorEvent(error)))
                    } else {
                        fulfilled(.success(tpm))
                    }
                }
            }
        }
    }
}

public func removeFromPreferences<T: TunnelProviderManager>(_ tpm: T)
    -> Effect<Result<(), ErrorEvent<NEVPNError>>>
{
    Effect.deferred { fulfilled in
        tpm.remove { maybeError in
            if let error = maybeError {
                fulfilled(.failure(ErrorEvent(error)))
            } else {
                fulfilled(.success(()))
            }
        }
    }

}

/// Updates `VPNConnectionObserver` to observe VPN status change.
public func observeConnectionStatus<T: TunnelProviderManager>(
    for tpm: T, observer: VPNConnectionObserver<T>
) {
    observer.setTunnelProviderManager(tpm)
}

/// Sends message do the tunnel provider if it is active.
/// If not active, an error event with value `ProviderMessageError.providerNotActive` is sent.
public func sendMessage<T: TunnelProviderManager>(
    toProvider tpm: T, data: Data
) -> Effect<(T, TunnelProviderVPNStatus, Result<Data, ErrorEvent<ProviderMessageSendError>>)> {
    Effect.deferred { fulfilled in
        let connectionStatus = tpm.connectionStatus
        guard connectionStatus.providerNotStopped else {
            fulfilled((tpm, connectionStatus, .failure(ErrorEvent(.providerNotActive))))
            return
        }
        
        do {
            try tpm.sendProviderMessage(data) { maybeResponseData in
                // A response is always required from the tunnel provider.
                guard let responseData = maybeResponseData else {
                    fulfilled(
                        (tpm, connectionStatus, .failure(ErrorEvent(.parseError("nil response"))))
                    )
                    return
                }
                fulfilled((tpm, connectionStatus, .success(responseData)))
            }
        } catch {
            let vpnError = NEVPNError(_nsError: error as NSError)
            fulfilled((tpm, connectionStatus, .failure(ErrorEvent(.neVPNError(vpnError)))))
        }
    }
}

// MARK: Connection status observer

public final class PsiphonTPMConnectionObserver: VPNConnectionObserver<PsiphonTPM> {
    
    private weak var tunnelProviderManager: PsiphonTPM? = nil
    
    /// - Note: Removes previous `NEVPNStatusDidChange` NSNotification observer if any.
    override func setTunnelProviderManager(_ manager: PsiphonTPM) {
        if let current = self.tunnelProviderManager {
            NotificationCenter.default.removeObserver(self, name: .NEVPNStatusDidChange,
                                                      object: current.wrappedManager.connection)
        }
        self.tunnelProviderManager = manager
        NotificationCenter.default.addObserver(self, selector: #selector(statusDidChange),
                                               name: .NEVPNStatusDidChange,
                                               object: manager.wrappedManager.connection)
        
        // Updates the tunnel with the current status before
        // notifications for status change kick in.
        statusDidChange()
    }
    
    @objc private func statusDidChange() {
        // statusDidChange callback can be called even after previous tunnel provider manager
        // has been deallocated.
        // It is valid in this case to send store with `NEVPNStatusInvalid`.
        guard let manager = self.tunnelProviderManager else {
            storeSend(.invalid)
            return
        }
        storeSend(manager.connectionStatus as TunnelProviderVPNStatus)
    }
    
}

// MARK: PsiphonTPM feedback description

extension PsiphonTPM: CustomStringFeedbackDescription {

    public var description: String {
        // `description` of NETunnelProviderManager looks something like below:
        //
        // "{\n    localizedDescription = Psiphon\n    enabled = YES\n
        // protocolConfiguration = {\n        serverAddress = <9-char-str>\n
        // disconnectOnSleep = NO\n        includeAllNetworks = NO\n
        // excludeLocalNetworks = NO\n
        // providerBundleIdentifier = ca.psiphon.Psiphon.PsiphonVPN\n    }\n
        // onDemandEnabled = NO\n    onDemandRules = (\n
        // {\n            action = connect\n
        // interfaceTypeMatch = any\n        },\n    )\n}"
        //
        // To make a readable string without newline characters, some simple processing is done,
        // the result of which looks like this:
        //
        // "{ localizedDescription = Psiphon enabled = YES
        // protocolConfiguration = { serverAddress = <9-char-str> disconnectOnSleep = NO
        // includeAllNetworks = NO excludeLocalNetworks = NO
        // providerBundleIdentifier = ca.psiphon.Psiphon.PsiphonVPN }
        // onDemandEnabled = NO
        // onDemandRules = ( { action = connect interfaceTypeMatch = any }, ) }"
        
        String(describing: self.wrappedManager)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

}
