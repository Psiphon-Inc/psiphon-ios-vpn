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
import Promises
import AppStoreIAP
import PsiApi

/// Represents data associated with a feedback.
struct SubmitFeedbackData: Equatable {
    let selectedThumbIndex: Int
    let comments: String
    let email: String
    let uploadDiagnostics: Bool
    
    /// `True` if the app asked the user to send a feedback due to an error condition.
    let errorInitiated: Bool
    
}

enum FeedbackAction {
    
    /// Informational message for logging.
    case _log(String)

    /// Upload the next user feedback in the queue.
    case _sendNextFeedback

    /// A diagnostic notice emitted by the configured feedback upload provider.
    case _feedbackUploadProviderNotice(Notice)

    /// The feedback upload operation has completed.
    /// If error is non-nil, then the operation failed with the provided error.
    case _feedbackUploadProviderCompleted(Error?)

    /// The user submitted an in-app feedback.
    case userSubmittedFeedback(SubmitFeedbackData)
}

struct FeedbackReducerState: Equatable {
    
    var queuedFeedbacks: [UserFeedback]
    
    // TODO: FeedbackUpload is not a value type, and should not be part of the state.
    var feedbackUpload: FeedbackUpload? // initialized lazily

    init(queuedFeedbacks: [UserFeedback]) {
        self.queuedFeedbacks = queuedFeedbacks
    }
}

struct FeedbackReducerEnvironment {
    let feedbackLogger: FeedbackLogger
    let getFeedbackUpload: () -> FeedbackUploadProvider
    let tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>
    let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    let subscriptionStatusSignal: SignalProducer<AppStoreIAP.SubscriptionStatus, Never>
    let getAppStateFeedbackEntry:  SignalProducer<DiagnosticEntry, Never>
    let sharedDB: PsiphonDataSharedDB
    let userConfigs: UserDefaultsConfig
    let appInfo: () -> AppInfoProvider
    let getPsiphonConfig: () -> [AnyHashable: Any]?
    let getCurrentTime: () -> Date
    let mainViewStore: (MainViewAction) -> Effect<Never>

    init(
        feedbackLogger: FeedbackLogger,
        getFeedbackUpload: @escaping () -> FeedbackUploadProvider,
        tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        subscriptionStatusSignal: SignalProducer<AppStoreIAP.SubscriptionStatus, Never>,
        getAppStateFeedbackEntry: SignalProducer<DiagnosticEntry, Never>,
        sharedDB: PsiphonDataSharedDB,
        userConfigs: UserDefaultsConfig,
        appInfo: @escaping () -> AppInfoProvider,
        getPsiphonConfig: @escaping () -> [AnyHashable: Any]?,
        getCurrentTime: @escaping () -> Date,
        mainViewStore: @escaping (MainViewAction) -> Effect<Never>
    ) {
        self.feedbackLogger = feedbackLogger
        self.getFeedbackUpload = getFeedbackUpload
        self.tunnelStatusSignal = tunnelStatusSignal
        self.tunnelConnectionRefSignal = tunnelConnectionRefSignal
        self.subscriptionStatusSignal = subscriptionStatusSignal
        self.getAppStateFeedbackEntry = getAppStateFeedbackEntry
        self.sharedDB = sharedDB
        self.userConfigs = userConfigs
        self.appInfo = appInfo
        self.getPsiphonConfig = getPsiphonConfig
        self.getCurrentTime = getCurrentTime
        self.mainViewStore = mainViewStore
    }
}

let feedbackReducer = Reducer<FeedbackReducerState,
           FeedbackAction,
           FeedbackReducerEnvironment> { state, action, environment in
    
    switch action {
    case ._log(let message):
        return [
            environment.feedbackLogger.log(.info, LogMessage(stringLiteral: message)).mapNever()
        ]
    case ._feedbackUploadProviderNotice(let notice):
        return [
            environment.feedbackLogger.logNotice(type: "FeedbackUpload(tunnel-core)",
                                                 value: notice.message,
                                                 timestamp: notice.timestamp).mapNever()
        ]
    case ._feedbackUploadProviderCompleted(let error):
        let userFeedback = state.queuedFeedbacks.removeFirst()

        var effects = [Effect<FeedbackAction>]()

        if state.queuedFeedbacks.count > 0 {
            // Start next upload.
            effects += Effect(value: ._sendNextFeedback)
        } else {
            // Allow upload provider to be deallocated
            state.feedbackUpload = .none;
        }

        if let uploadError = error {
            return [
                environment.feedbackLogger.log(.info, LogMessage(stringLiteral: "upload failed: \(uploadError)")).mapNever()
            ] + effects
        } else {
            return [
                environment.feedbackLogger.log(.info, "upload succeeded").mapNever(),
                
                // Records date of last successful feedback submit time.
                .fireAndForget {
                    environment.userConfigs.lastFeedbackSubmitTime = userFeedback.submitTime
                }
                
            ] + effects
        }
    case ._sendNextFeedback:

        if case .none = state.feedbackUpload {
            state.feedbackUpload = FeedbackUpload(feedbackUploadProvider: environment.getFeedbackUpload());
        }
        let feedbackUpload = state.feedbackUpload!

        if let nextFeedback = state.queuedFeedbacks.first {
            return [
                environment.feedbackLogger.log(
                    .info, LogMessage(stringLiteral: "uploading feedback")).mapNever(),
                sendFeedback(userFeedback: nextFeedback, feedbackUpload: feedbackUpload, environment: environment)
            ]
        }
        return []
        
    case .userSubmittedFeedback(let submitFeedbackData):
        // Generate feedback ID once per user feedback.
        // Using the same feedback ID for each upload attempt makes it easier to identify when a
        // feedback has been uploaded more than once, e.g. the upload succeeds but the connection
        // with the server is disrupted before the response is received by the client.
        guard let randomFeedbackId = Feedback.generateId() else {
            return [
                environment.feedbackLogger.log(.error, "failed to generate random feedback ID")
                    .mapNever()
            ]
        }
        
        let currentTime = environment.getCurrentTime()
        
        state.queuedFeedbacks.append(
            UserFeedback(
                selectedThumbIndex: submitFeedbackData.selectedThumbIndex,
                comments: submitFeedbackData.comments,
                email: submitFeedbackData.email,
                uploadDiagnostics: submitFeedbackData.uploadDiagnostics,
                feedbackId: randomFeedbackId,
                submitTime: currentTime,
                errorInitiated: submitFeedbackData.errorInitiated
            )
        )
        
        var effects = [Effect<FeedbackAction>]()
        
        let alertEvent = AlertEvent(.submittedFeedbackAlert, date: currentTime)
        
        effects += environment.mainViewStore(.presentAlert(alertEvent)) .mapNever()

        if state.queuedFeedbacks.count > 1 {
            return effects
        }
        // Kick off uploads.
        return effects + [ Effect(value: ._sendNextFeedback) ]
    }
}

/// Signal which encapsulates the feedback upload operation.
///
/// The upload will be started once there is network connectivity and VPN is
/// disconnected or connected. If the state changes while an upload is ongoing (e.g.
/// VPN state changes from connected to disconnecting, or the subscription status
/// changes), then the ongoing upload is cancelled and automatically retried by
/// restarting the upload when the required preconditions are met again.
///
/// - Warning: If the state keeps changing before the upload completes, then
/// the upload could be retried indefinitely. In the future it could be desirable to
/// restrict the number of retries in this signal, or propagate the retry number to
/// the feedback upload provider and allow the implementer to decide when to stop
/// retrying.
///   
/// - Parameters:
///   - userFeedback: User feedback to upload.
///   - feedbackUpload: Instance which will facilitate the feedback upload.
///   - environment: Reducer environment.
/// - Returns: Cold signal which will perform the feedback upload operation once observed. The signal emits FeedbackAction items
/// to signal when the upload has completed and to perform logging.
fileprivate func sendFeedback(userFeedback: UserFeedback,
                              feedbackUpload: FeedbackUpload,
                              environment: FeedbackReducerEnvironment) -> Effect<FeedbackAction> {

    // Breaking this expression out helps the type checker reason about the type of the
    // following signal chain.
    let triggers =
        SignalProducer
        .combineLatest(environment.tunnelStatusSignal,
                       environment.tunnelConnectionRefSignal,
                       environment.subscriptionStatusSignal)

    return
        triggers
        .skipRepeats({ (lhs, rhs) -> Bool in
             return lhs == rhs
         })
        .flatMap(.latest) { (value: (TunnelProviderVPNStatus,
                                     TunnelConnection?, AppStoreIAP.SubscriptionStatus))
            -> SignalProducer<SignalTermination<FeedbackAction>, Never> in

            let vpnStatus = value.0
            guard vpnStatus == .invalid ||
                    vpnStatus == .disconnected ||
                    vpnStatus == .connected else {
                return
                    SignalProducer(value: .value(._log("waiting for VPN to be disconnected or connected")))
            }

            guard let psiphonConfig = environment.getPsiphonConfig() else {
                return
                    SignalProducer(value:.terminate)
                    .prefix(value: .value(._feedbackUploadProviderCompleted(.some(ErrorRepr(repr: "Psiphon config nil")))))
            }

            // Do not use upstream proxy for upload if the VPN could be connected.
            let useUpstreamProxy =
                vpnStatus == .invalid ||
                vpnStatus == .disconnecting ||
                vpnStatus == .disconnected

            let subscriptionStatus = value.2
            switch feedbackUploadPsiphonConfig(basePsiphonConfig: psiphonConfig,
                                               useUpstreamProxy: useUpstreamProxy,
                                               subscriptionStatus: subscriptionStatus,
                                               appInfo: environment.appInfo()) {

            case .success(let psiphonConfig):
                return environment.getAppStateFeedbackEntry.take(first: 1).flatMap(.latest) { appStateFeedbackEntry in
                    let feedback =
                        feedbackJSON(userFeedback: userFeedback,
                                     psiphonConfig: psiphonConfig,
                                     appStateFeedbackEntry: appStateFeedbackEntry,
                                     sharedDB: environment.sharedDB,
                                     getCurrentTime: environment.getCurrentTime)

                    switch feedback {
                    case .success(let feedbackJSON):

                            // Last moment VPN status check.
                            if let tunnelConnection = value.1 {
                                if case .connection(let tunnelConnectionVPNStatus) = tunnelConnection.connectionStatus() {
                                    guard tunnelConnectionVPNStatus == .invalid ||
                                            tunnelConnectionVPNStatus == .disconnected ||
                                            tunnelConnectionVPNStatus == .connected else {
                                        return
                                            SignalProducer(value: .value(
                                                            ._log("waiting for VPN to be disconnected or connected")))
                                    }
                                }
                            }

                            // Note: It is possible that the upload could succeed at the same moment
                            // one of the trigger signals (VPN state change, etc.) changes. Then
                            // there would be a race between this signal emitting a value and it
                            // being disposed of, which would result in the value being ignored. If
                            // this happens, the feedback upload will be attempted again even though
                            // it already succeeded. For this reason the same feedback ID is used
                            // for all upload attempts, which will provide visibility into these
                            // occurrences and allow for mitigation.
                            return
                                feedbackUpload.sendFeedback(feedbackJson: feedbackJSON,
                                                            feedbackConfigJson: psiphonConfig)
                                .flatMap(.concat) {
                                    (value: FeedbackUploadProviderResult)
                                    -> SignalProducer<SignalTermination<FeedbackAction>, Never> in
                                    switch value {
                                    case .notice(let notice):
                                        return SignalProducer(value:.value(._feedbackUploadProviderNotice(notice)))
                                    case .completed(let error):
                                        return
                                            SignalProducer(value:.terminate)
                                            .prefix(value: .value(._feedbackUploadProviderCompleted(error)))
                                    }
                                }

                    case .failure(let error):
                        return
                            SignalProducer(value:.terminate)
                            .prefix(value:.value(._feedbackUploadProviderCompleted(.some(error))))
                    }
                }

            case .failure(let error):
                return
                    SignalProducer(value:.terminate)
                    .prefix(value:.value(._feedbackUploadProviderCompleted(.some(error))))
            }

         }
        .take(while: { (signalTermination: SignalTermination<FeedbackAction>) -> Bool in
            // Forwards values while the `.terminate` value has not been emitted.
            guard case .value(_) = signalTermination else {
                return false
            }
            return true
        })
        .map { (signalTermination: SignalTermination<FeedbackAction>) -> FeedbackAction in
            guard case let .value(action) = signalTermination else {
                fatalError()
            }
            return action
        }
}
