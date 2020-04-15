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

// Feedback description note:
// For new fields that are added, the feedback description in FeedbackDescriptions.swift
// should also be updated.

final class UserDefaultsConfig {

    /// Expected PsiCash reward while waiting for a successful PsiCash refresh state.
    @JSONUserDefault(.standard, "psicash_expected_reward_v1",
                     defaultValue: PsiCashAmount.zero())
    var expectedPsiCashReward: PsiCashAmount

}
