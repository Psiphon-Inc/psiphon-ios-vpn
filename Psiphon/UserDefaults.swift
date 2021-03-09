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
import PsiApi
import PsiCashClient

// Feedback description note:
// For new fields that are added, the feedback description in FeedbackDescriptions.swift
// should also be updated.
final class UserDefaultsConfig: PsiCashPersistedValues {

    /// Expected PsiCash reward while waiting for a successful PsiCash refresh state.
    // TODO: Pass in feedback logger as a dependency.
    @JSONUserDefault(.standard, "psicash_expected_reward_v1",
                     defaultValue: PsiCashAmount.zero,
                     errorLogger: FeedbackLogger(PsiphonRotatingFileFeedbackLogHandler()))
    var expectedPsiCashReward: PsiCashAmount

    func setExpectedPsiCashReward(_ value: PsiCashAmount) {
        self.expectedPsiCashReward = value
    }
    
    /// App language code.
    @UserDefault(.standard, "appLanguage", defaultValue: Language.defaultLanguageCode)
    var appLanguage: String
    
    /// Set of onboardings that have been completed by the user.
    @UserDefault(.standard, "onboarding_stages_completed", defaultValue: [])
    var onboardingStagesCompleted: [String]
    
    @UserDefault(.standard, "LastCFBundleVersion", defaultValue: "")
    var lastBundleVersion: String

    // TODO: The value here is not accessed directly though PsiCashEffects,
    // but rather indirectly through PsiCash class migrateTokens method.
    /// Represents the latest PsiCash data store version that the app has migrated to.
    ///
    /// Versions:
    /// 0 (default): First PsiCash client version that uses NSUserDefaults as data store.
    /// 1: Skipped.
    /// 2: PsiCash client based on psicash-lib-core that uses a file as data store.
    @UserDefault(.standard, "Psiphon-PsiCash-DataStore-Migrated-Version", defaultValue: 0)
    var psiCashDataStoreMigratedToVersion: Int
}

extension UserDefaultsConfig {
    
    /// Returned `onboardingStagesCompleted` parsed into types.
    /// Drops values that are not recognized by `OnboardingStage`.
    var onboardingStagesCompletedTyped: [OnboardingStage] {
        return self.onboardingStagesCompleted.compactMap(OnboardingStage.init(rawValue:))
    }
    
    /// Returns Locale object for user-selected app language.
    /// - Note: that this can be different from device locale value `Locale.current`.
    // TODO: Needs a check if the stored user default app language may have been removed.
    var localeForAppLanguage: Locale {
        let langIdentifier = self.appLanguage
        switch langIdentifier {
        case Language.defaultLanguageCode:
            return Locale.current
        default:
            return Locale(identifier: langIdentifier)
        }
    }
    
}
