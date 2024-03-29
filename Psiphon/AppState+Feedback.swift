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
import ReactiveSwift

struct AppStateFeedbackEntryJSON: Encodable {
    
    let AppState: String
    let PsiCashLib: String
    let UserDefaultsConfig: String
    let PsiphonDataSharedDB: String
    let OutstandingEffectCount: Int
    
}

extension AppState {

    /// `feedbackEntry` returns a diagnostic entry which captures the current app state for logging.
    func feedbackEntry<Value, Action>(
        userDefaultsConfig: UserDefaultsConfig,
        sharedDB: PsiphonDataSharedDB,
        store: Store<Value, Action>,
        psiCashLib: PsiCashLib
    ) -> DiagnosticEntry {
        
        let jsonObj = AppStateFeedbackEntryJSON(
            AppState: makeFeedbackEntry(self),
            PsiCashLib: psiCashLib.getDiagnosticInfo(lite: false),
            UserDefaultsConfig: makeFeedbackEntry(UserDefaultsConfig()),
            PsiphonDataSharedDB: makeFeedbackEntry(sharedDB),
            OutstandingEffectCount: store.outstandingEffectCount
        )
        
        do {
            let jsonData = try JSONEncoder().encode(jsonObj)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return DiagnosticEntry("ContainerInfo: \(jsonString)", andTimestamp: Date())
            } else {
                return DiagnosticEntry("Failed to decode data with UTF-8")
            }
        } catch {
            return DiagnosticEntry("Failed to encode: \(error)", andTimestamp: Date())
        }
        
    }

}
