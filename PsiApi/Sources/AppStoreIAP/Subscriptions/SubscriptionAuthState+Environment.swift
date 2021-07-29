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

public struct SubscriptionAuthStateReducerEnvironment {
    
    public let feedbackLogger: FeedbackLogger
    public let httpClient: HTTPClient
    public let httpRequestRetryCount: Int
    public let httpRequestRetryInterval: DispatchTimeInterval
    public let notifier: Notifier
    public let notifierUpdatedAuthorizationsMessage: String
    public let sharedAuthCoreData: SharedAuthCoreData
    public let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    public let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    public let clientMetaData: () -> ClientMetaData
    public let dateCompare: DateCompare
    public let mainDispatcher: MainDispatcher
    
    public init(
        feedbackLogger: FeedbackLogger,
        httpClient: HTTPClient,
        httpRequestRetryCount: Int,
        httpRequestRetryInterval: DispatchTimeInterval,
        notifier: Notifier,
        notifierUpdatedAuthorizationsMessage: String,
        sharedAuthCoreData: SharedAuthCoreData,
        tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        clientMetaData: @escaping () -> ClientMetaData,
        dateCompare: DateCompare,
        mainDispatcher: MainDispatcher
    ) {
        self.feedbackLogger = feedbackLogger
        self.httpClient = httpClient
        self.httpRequestRetryCount = httpRequestRetryCount
        self.httpRequestRetryInterval = httpRequestRetryInterval
        self.notifier = notifier
        self.notifierUpdatedAuthorizationsMessage = notifierUpdatedAuthorizationsMessage
        self.sharedAuthCoreData = sharedAuthCoreData
        self.tunnelStatusSignal = tunnelStatusSignal
        self.tunnelConnectionRefSignal = tunnelConnectionRefSignal
        self.clientMetaData = clientMetaData
        self.dateCompare = dateCompare
        self.mainDispatcher = mainDispatcher
    }
}
