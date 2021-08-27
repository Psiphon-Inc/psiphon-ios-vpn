/*
 * Copyright (c) 2021, Psiphon Inc.
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
import ReactiveSwift
import PsiphonClientCommonLibrary

enum ServerRegionAction: Equatable {
    
    /// User selected a server region
    case userSelectedRegion(region: Region)
    
    /// Updates selected region, and list of available regions, either from embedded server regions
    /// or from the list of regions emitted by the Psiphon tunnel.
    case updateAvailableRegions
    
    case _updatedAvailableRegions(selectedRegion: Region,
                                  availableRegions: Result<Set<String>, ErrorMessage>)
}

struct ServerRegionState: Equatable {
    
    /// Value is `nil` if persisted value has not been loaded yet.
    var selectedRegion: Region?
    
    /// Set of available regions, represented by their region code.
    /// Value is `nil` if persisted value has not been loaded yet.
    var availableRegions: Set<String>?
    
}

struct ServerRegionEnvironment {
    let regionAdapter: RegionAdapter
    let sharedDB: PsiphonDataSharedDB
    let readEmbeddedServerEntries: () -> Effect<Result<Set<String>, ErrorMessage>>
    let tunnelIntentStore: (TunnelStartStopIntent) -> Effect<Never>
    let feedbackLogger: FeedbackLogger
}

let serverRegionReducer = Reducer<ServerRegionState,
                                    ServerRegionAction,
                                    ServerRegionEnvironment> {
    state, action, environment in
    
    switch action {
    case .userSelectedRegion(region: let newRegion):
        
        let restartVPN = state.selectedRegion?.code != newRegion.code!
        
        state.selectedRegion = newRegion
        
        return [
            .fireAndForget {
                environment.regionAdapter.setSelectedRegion(newRegion.code)
                CopySettingsToPsiphonDataSharedDB.sharedInstance.copySelectedRegion()
            }.then(
                // Restarts the VPN if it is already active.
                Effect(value: restartVPN)
                    .flatMap(.latest, { restartVPN in
                        if restartVPN {
                            return environment.tunnelIntentStore(.start(transition: .restart))
                                .mapNever()
                        } else {
                            return .empty
                        }
                    }).mapNever()
            ),
            
            environment.feedbackLogger.log(
                .info, "User selected egress region: '\(newRegion.code!)'")
                .mapNever()
            
        ]
        
    case .updateAvailableRegions:
        
        // TODO: Returned effect runs too many times, most of the time doing unnecessary work.
        
        return [
            
            // Returned effect emits  set of egress regions emitted by tunnel-core
            // if available, emits the embedded server regions.
            Effect.deferred { () -> [String]? in
                
                #if DEBUG
                // fake the availability of all regions in the UI for automated screenshots
                if AppInfo.runningUITest() {
                    let fakeRegions = (environment.regionAdapter.getRegions() as! [Region])
                        .compactMap { $0.code }
                    return fakeRegions
                }
                #endif
                
                return environment.sharedDB.emittedEgressRegions()
                
            }.flatMap(.latest, { (emittedEgressRegions: [String]?)
                -> Effect<Result<Set<String>, ErrorMessage>> in
                
                if let emittedEgressRegions = emittedEgressRegions {
                    return Effect(value: .success(Set(emittedEgressRegions)))
                } else {
                    // Embedded server regions are used if egress regions
                    // have never been set by tunnel-core.
                    return environment.readEmbeddedServerEntries()
                }
                
            }).flatMap(.latest, { (availableRegionCodes: Result<Set<String>, ErrorMessage>)
                -> Effect<(Region, Result<Set<String>, ErrorMessage>)> in
                
                // onAvailableEgressRegions should be called before getting selected region
                // from RegionAdapter. Since selected regions might change to "Best Performance"
                // if it is no longer an available region.
                
                if case let .success(availableRegionCodes) = availableRegionCodes {
                    // Updates RegionAdapter with available egress regions.
                    environment.regionAdapter.onAvailableEgressRegions(Array(availableRegionCodes))
                }
                
                guard let selectedRegion = environment.regionAdapter.getSelectedRegion() else {
                    fatalError("Expected non-nil region")
                }
                
                return Effect(value: (selectedRegion, availableRegionCodes))
                
            }).map{
                ._updatedAvailableRegions(selectedRegion: $0.0, availableRegions: $0.1)
            }
            
        ]
    
    case let ._updatedAvailableRegions(selectedRegion: selectedRegion,
                                       availableRegions: availableRegionsResult):
        
        switch availableRegionsResult {
        case .success(let availableRegions):
            state.selectedRegion = selectedRegion
            state.availableRegions = availableRegions
            return [
                .fireAndForget {
                    CopySettingsToPsiphonDataSharedDB.sharedInstance.copySelectedRegion()
                }
            ]
            
        case .failure(let errorMessage):
            environment.feedbackLogger.fatalError(
                "Failed getting region codes: \(errorMessage.message)")
            return []
            
        }
        
        
    }
    
}
