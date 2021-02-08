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

// This is a hack.
// SWIFT_ACTIVE_COMPILATION_CONDITIONS defined in the Xcode project
// is only applied to the app target 'Psiphon'.
// Compilation conditions can be defined for each target in this framework's `Package.swift`
// file, however there seems to be no way to pass along conditions defined in
// SWIFT_ACTIVE_COMPILATION_CONDITIONS in the xcodeproj file.
// Another options is to explicitly pass some kind of environment variable in all places
// where `Debugging` is used. However, the cost seems to outweight the benefits at this point.
public var Debugging: DebugFlags! = nil

public struct DebugFlags {

    public enum BuildConfig: String {
        case debug = "Debug"
        case devRelease = "DevRelease"
        case release = "Release"
    }

    public var buildConfig: BuildConfig
    public var mainThreadChecks: Bool
    public var disableURLHandler: Bool
    public var devServers: Bool
    public var ignoreTunneledChecks: Bool
    public var disableConnectOnDemand: Bool
    public var adNetworkGeographicDebugging: AdNetworkGeographicDebugging = .disabled

    
    public var printStoreLogs: Bool
    public var printAppState: Bool
    public var printHttpRequests: Bool

    public init(
        buildConfig: DebugFlags.BuildConfig,
        mainThreadChecks: Bool = true,
        disableURLHandler: Bool = false,
        devServers: Bool = true,
        ignoreTunneledChecks: Bool = false,
        disableConnectOnDemand: Bool = false,
        adNetworkGeographicDebugging: .disabled,
        printStoreLogs: Bool = false,
        printAppState: Bool = false,
        printHttpRequests: Bool = false
    ) {
        self.buildConfig = buildConfig
        self.mainThreadChecks = mainThreadChecks
        self.disableURLHandler = disableURLHandler
        self.devServers = devServers
        self.ignoreTunneledChecks = ignoreTunneledChecks
        self.disableConnectOnDemand = disableConnectOnDemand
        self.adNetworkGeographicDebugging = adNetworkGeographicDebugging,
        self.printStoreLogs = printStoreLogs
        self.printAppState = printAppState
        self.printHttpRequests = printHttpRequests
    }
    
    public static func disabled(buildConfig: BuildConfig) -> Self {
        .init(
            buildConfig: buildConfig,
            mainThreadChecks: false,
            disableURLHandler: false,
            devServers: false,
            ignoreTunneledChecks: false,
            disableConnectOnDemand: false,
            printStoreLogs: false,
            printAppState: false,
            printHttpRequests: false
        )
    }
}

public enum AdNetworkGeographicDebugging: Equatable {
    /// Geographic debugging is disabled.
    case disabled
    /// Geography appears as in EEA for debug devices that are set.
    case EEA
    /// Geography appears as not in EEA for debug devices that are set.
    case notEEA
}
