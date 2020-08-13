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
import PsiApi

@objc final class AppUpgrade: NSObject {
    
    /// Value is `nil` until `checkForUpgrade` is called.
    var newInstallation: Bool? = nil
    
    /// Value is `nil` until `checkForUpgrade` is called.
    var firstRunOfVersion: Bool? = nil
    
    private var checkedForUpgrade = false
    
    override init() {}
    
    func checkForUpgrade(
        userDefaultsConfig: UserDefaultsConfig,
        appInfo: AppInfoProvider,
        feedbackLogger: FeedbackLogger
    ) {
        guard !self.checkedForUpgrade else {
            return
        }
        
        self.checkedForUpgrade = true
        
        let lastBundleVersion = userDefaultsConfig.lastBundleVersion
        let currentVersion = appInfo.clientVersion
        
        self.newInstallation = lastBundleVersion.isEmpty
        
        if currentVersion == lastBundleVersion {
            self.firstRunOfVersion = false
        } else {
            self.firstRunOfVersion = true
                        
            if lastBundleVersion.isEmpty {
                feedbackLogger.immediate(.info, "New installation '\(currentVersion)'")
            } else {
                feedbackLogger.immediate(
                    .info, "App upgrade from '\(lastBundleVersion)' to '\(currentVersion)'")
                
                // Handle app upgrades.
                handleAppUpgradeFromVersion(
                    oldVersion: lastBundleVersion,
                    userDefaultsConfig: userDefaultsConfig
                )
            }
            
            userDefaultsConfig.lastBundleVersion = currentVersion
            
        }
        
    }
    
}

/// For safety and simplicity, only `oldVersionString` is provided here.
/// Should not rely on the current build number, as that build number is not specified yet.
func handleAppUpgradeFromVersion(oldVersion: String, userDefaultsConfig: UserDefaultsConfig) {
    guard !oldVersion.isEmpty else {
        fatalError()
    }
    
    guard let oldVersionInt = Int(oldVersion) else {
        fatalError("version is not an integer")
    }
    
    if oldVersionInt <= 106 {
        // Deletes unused NSUserDefaults keys below
        let legacyKeysToDelete = [
            legacy_106_privacyPolicyAcceptedBoolKey,
            legacy_106_privacyPolicyAcceptedRFC3339Key
        ]
        
        for key in legacyKeysToDelete {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    if oldVersionInt <= 175 {
        // Delete unused NSUserDefaults PsiCash onboarding key
        UserDefaults.standard.removeObject(forKey: legacy_175_psiCashHasBeenOnboardedKey)
        
        
        // If stored value under key `"ContainerDB.FinishedOnboardingBoolKey"` is true,
        // `userDefaultsConfig` is updated to the equivalent value, and the key deleted.
        let finishedOnboarding =  UserDefaults.standard.bool(
            forKey: legacy_175_containerFinishedOnboardingKey)
        
        if finishedOnboarding {
            let completedStages: [OnboardingStage] = [
                .languageSelection, .privacyPolicy_v2018_05_15, .vpnConfigPermission
            ]
            
            userDefaultsConfig.onboardingStagesCompleted = completedStages.map(\.rawValue)
        }
        
        UserDefaults.standard.removeObject(forKey: legacy_175_containerFinishedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: legacy_175_privacyPolicyAcceptedTimeKey)
    }
    
}

// MARK: List of legacy NSUserDefaults keys
let legacy_106_privacyPolicyAcceptedBoolKey = "PrivacyPolicy.AcceptedBoolKey"
let legacy_106_privacyPolicyAcceptedRFC3339Key = "ContainerDB.PrivacyPolicyAcceptedRFC3339StringKey"
let legacy_175_psiCashHasBeenOnboardedKey = "PsiCash.HasBeenOnboarded"
let legacy_175_containerFinishedOnboardingKey = "ContainerDB.FinishedOnboardingBoolKey"
let legacy_175_privacyPolicyAcceptedTimeKey = "ContainerDB.PrivacyPolicyAcceptedStringTimeKey2"
