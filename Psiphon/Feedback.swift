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
import AppStoreIAP
import PsiApi
import ReactiveSwift
import PsiphonClientCommonLibrary

/// A type that can be used for uploading feedback data.
public protocol FeedbackUploadProvider {

    /// Start sending the feedback data. This call is asynchronous and returns before the upload completes.
    /// - Parameters:
    ///   - feedbackJson: The feedback data to upload.
    ///   - feedbackConfigJson: The configuration to be used for uploading the feedback.
    ///   - uploadPath: Path which will be appended to any feedback upload URI used for the upload operation.
    ///   - logger: Logger which will be called with any informational notices.
    ///   - feedbackDelegate: Delegate which will be called once when the upload completes.
    func startUpload(feedbackJson: String,
                     feedbackConfigJson: [AnyHashable: Any],
                     uploadPath: String,
                     logger: PsiphonTunnelLoggerDelegate,
                     feedbackDelegate: PsiphonTunnelFeedbackDelegate)

    /// Signals the provider to interrupt any feedback uploads in progress.
    func stopUpload()

}

/// A type which represents a user feedback submitted with the in-app feedback form.
public struct UserFeedback: Equatable {
    let selectedThumbIndex: Int
    let comments: String
    let email: String
    let uploadDiagnostics: Bool
    let submitTime: Date
    let feedbackId: String
    
    /// `true` if the feedback submitted is initiated due to an error condition
    let errorInitiated: Bool

    public init(selectedThumbIndex: Int, comments: String, email: String,
                uploadDiagnostics: Bool, feedbackId: String, submitTime: Date,
                errorInitiated: Bool) {

        self.selectedThumbIndex = selectedThumbIndex
        self.comments = comments
        self.email = email
        self.uploadDiagnostics = uploadDiagnostics
        self.feedbackId = feedbackId
        self.submitTime = submitTime
        self.errorInitiated = errorInitiated
    }
}

/// A type which represents a notice emitted from the feedback upload operation.
public struct Notice {

    /// Diagnostic message string.
    let message: String

    /// RFC3339 encoded timestamp.
    let timestamp: String

}

/// Values which can be emitted from a feedback upload operation.
public enum FeedbackUploadProviderResult {

    /// Diagnostic log emitted during the upload operation.
    case notice(Notice)

    /// Signals that the feedback operation has been completed. No more values will be emitted.
    /// If error is non-nil, then the operation failed with the provided error.
    case completed(Error?)
}

/// Interface which exposes `FeedbackUploadProvider` callbacks as closures.
fileprivate final class FeedbackHandler : NSObject,
                                          PsiphonTunnelLoggerDelegate,
                                          PsiphonTunnelFeedbackDelegate {

    let feedbackUploadProvider: FeedbackUploadProvider

    var completionHandler: (Error?) -> ()
    var noticeHandler: (Notice) -> ()

    public init(feedbackUploadProvider: FeedbackUploadProvider,
                completionHandler: @escaping (Error?) -> (),
                noticeHandler: @escaping (Notice) -> ()) {
        self.feedbackUploadProvider = feedbackUploadProvider
        self.completionHandler = completionHandler
        self.noticeHandler = noticeHandler
        super.init()
    }

    public func sendFeedback(feedbackJson: String,
                             feedbackConfigJson: [AnyHashable: Any]) {
        self.feedbackUploadProvider.startUpload(feedbackJson: feedbackJson,
                                                feedbackConfigJson: feedbackConfigJson,
                                                uploadPath: "",
                                                logger: self,
                                                feedbackDelegate: self)
    }

    /// Interrupts any feedback upload operations in progress.
    public func stopSend() {
        self.feedbackUploadProvider.stopUpload()
    }

    /// `PsiphonTunnelLoggerDelegate` implementation.
    public func onDiagnosticMessage(_ message: String, withTimestamp timestamp: String) {
        self.noticeHandler(Notice(message: message, timestamp: timestamp))
    }

    /// `PsiphonTunnelSendFeedbackDelegate` implementation.
    public func sendFeedbackCompleted(_ err: Error?) {
        self.completionHandler(err)
    }
}

/// FeedbackUpload creates an interface around FeedbackUploadProvider which provides some guarantees with regards to call and
/// callback ordering by scheduling work on a serial queue.
///
/// - Note: An assumption is made that the underlying FeedbackUploadProvider only supports one upload at a time. This is true for
/// the implementation backed by the PsiphonTunnelFeedback class (provided by PsiphonTunnel.framework), which is used in production.
/// See the comments on the PsiphonTunnelFeedback class in PsiphonTunnel/PsiphonTunnel.h for more details. Therefore one
/// FeedbackUpload instance should be used to schedule all feedback upload work and using multiple instances to schedule, or stop,
/// work is unsupported and can result in undefined behavior.
final class FeedbackUpload: Equatable {

    static func == (lhs: FeedbackUpload, rhs: FeedbackUpload) -> Bool {
        return lhs === rhs
    }
    
    let feedbackUploadProvider: FeedbackUploadProvider
    let workQueue: DispatchQueue

    init(feedbackUploadProvider: FeedbackUploadProvider) {
        self.feedbackUploadProvider = feedbackUploadProvider
        self.workQueue = DispatchQueue(label: "ca.psiphon.Psiphon.feedbackUploadWorkQueue",
                                       qos: .background, attributes: .init(),
                                       autoreleaseFrequency: .inherit, target: DispatchQueue.global())
    }


    /// Returns a cold signal which will perform the feedback upload operation once observed. See `FeedbackUploadProviderResult`
    /// for more information on the items emitted. The upload will be cancelled if the returned signal is disposed of before it completes.
    ///
    /// - Warning: Only one upload is supported at a time and the returned signal must complete or be disposed before calling this
    /// function again.
    func sendFeedback(feedbackJson: String,
                      feedbackConfigJson: [AnyHashable: Any])
                     -> SignalProducer<FeedbackUploadProviderResult, Never> {
        // Note: Calls to the underlying FeedbackUploadProvider are synchronized to ensure that a
        // stopSend call intended for the current feedback upload operation does not get scheduled
        // after the sendFeedback call of the next upload; which would result in the next upload
        // being cancelled in error.
        return SignalProducer { [self] observer, lifetime in

            // Transform `FeedbackUploadProvider` callbacks into a stream of values.
            let f = FeedbackHandler(feedbackUploadProvider: self.feedbackUploadProvider, completionHandler: { [self] err in
                if !lifetime.hasEnded {
                    // Immediately return so we move off the callstack of sendCompleted
                    // callback: see PsiphonTunnel.h for more details.
                    self.workQueue.async {
                        observer.send(value: .completed(err))
                        observer.sendCompleted()
                    }
                }
            }, noticeHandler: { [self] notice in
                if !lifetime.hasEnded {
                    // Note: this closure will not be called after `completionHandler` is called.
                    self.workQueue.async {
                        observer.send(value:.notice(notice))
                    }
                }
            })
            lifetime.observeEnded {
                // Note: this call can trigger the completionHandler and noticeHandler callbacks and
                // they should check if the lifetime has ended to avoid doing unnecessary work.
                f.stopSend()
            }
            self.workQueue.async {
                f.sendFeedback(feedbackJson: feedbackJson, feedbackConfigJson: feedbackConfigJson)
            }
        }
    }
}

/// Adds fields required for a feedback upload operation to the default Psiphon config.
func feedbackUploadPsiphonConfig(basePsiphonConfig: [AnyHashable: Any],
                                 useUpstreamProxy: Bool,
                                 subscriptionStatus: AppStoreIAP.SubscriptionStatus,
                                 appInfo: AppInfoProvider) -> Result<[AnyHashable: Any], Error> {

    var config = basePsiphonConfig

    config["ClientVersion"] = appInfo.clientVersion

    // Configure data root directory.
    // PsiphonTunnel will store all of its files under this directory.

    guard let dataRootDirectory = PsiphonDataSharedDB.dataRootDirectory() else {
        return .failure(ErrorRepr(repr: "dataRootDirectory nil"))
    }

    let fileManager = FileManager.default
    do {
        // TODO: effect not parameterized
        try fileManager.createDirectory(at: dataRootDirectory,
                                        withIntermediateDirectories: true,
                                        attributes: .none)
    } catch {
        return .failure(ErrorRepr(repr:"failed to create dataRootDirectory: \(error)"))
    }

    config["DataRootDirectory"] = dataRootDirectory.path

    if case .subscribed(_) = subscriptionStatus {
        if let subscriptionConfig = config["subscriptionConfig"] as? [AnyHashable: Any] {
            if let subscribedSponsorId = subscriptionConfig["SponsorId"] as? String {
                config["SponsorId"] = subscribedSponsorId
            }
        }
    }

    if !useUpstreamProxy {
        config.removeValue(forKey: "UpstreamProxyUrl")
    }

    // TODO: effect not parameterized
    let psiphonTunnelUserConfigs = PsiphonDataSharedDB(
        forAppGroupIdentifier: PsiphonAppGroupIdentifier
    ).getTunnelCoreUserConfigs()
    
    config.merge(psiphonTunnelUserConfigs) { (_, new) in new }

    return .success(config)
}

/// Construct feedback JSON for upload.
/// - Returns: Result containing either the constructed feedback data for upload or an error if the operation failed.
func feedbackJSON(userFeedback: UserFeedback,
                  psiphonConfig: [AnyHashable: Any],
                  appStateFeedbackEntry: DiagnosticEntry,
                  sharedDB: PsiphonDataSharedDB,
                  getCurrentTime: () -> Date
) -> Result<String, Error> {
    
    let result = getFeedbackLogs(
        for: Set(FeedbackLogSource.allCases),
           dataRootDirectory: PsiphonDataSharedDB.dataRootDirectory(),
           getCurrentTime: getCurrentTime)
    
    // Only capture diagnostics logged before user submitted feedback.
    var diagnosticEntries = result.0.filter { entry in
        return entry.timestamp.compare(userFeedback.submitTime) == .orderedAscending
    }
    
    // Capture parse failures too.
    let parseFailureEntries = result.1.map {
        DiagnosticEntry($0.message, andTimestamp: $0.timestamp)!
    }
    diagnosticEntries.append(contentsOf: parseFailureEntries)
    
    // Adds a log line if the feedback is initiated due to an error condition in the app.
    if userFeedback.errorInitiated {
        diagnosticEntries.append(
            DiagnosticEntry("Error initiated feedback", andTimestamp: getCurrentTime()))
    }
    
    // Add jetsam metrics log.
    let binRanges = [
        // [0, 30s)
        BinRange(range: MakeCBinRange(0.00, 30.00)),
        // [30s, 60s)
        BinRange(range: MakeCBinRange(30.00, 60.00)),
        // [60s, 5m)
        BinRange(range: MakeCBinRange(60.00, 5*60.00)),
        // [5m, 10m)
        BinRange(range: MakeCBinRange(5*60.00, 10*60.00)),
        // [10m, 30m)
        BinRange(range: MakeCBinRange(10*60.00, 30*60.00)),
        // [30m, 1h)
        BinRange(range: MakeCBinRange(30*60.00, 60*60.00)),
        // [1h, 6h)
        BinRange(range: MakeCBinRange(60*60.00, 6*60*60.00)),
        // [6h, inf]
        BinRange(range: MakeCBinRange(6*60*60.00, Double.greatestFiniteMagnitude))
    ]

    do {
        // TODO: PsiphonTunnel:SendFeedback: now supports a completion callback, the registry used
        // by ContainerJetsamTracking should only be persisted once the feedback has been
        // successfully uploaded. Currently the registery is persisted before this call returns. If
        // the upload fails, then the metrics will be lost because the registry has already marked
        // them as processed and they will not be included a subsequent upload.
        // TODO: effects not parameterized (file system operations with default file manager)
        let metrics =
            try ContainerJetsamTracking
            .getMetricsFromFilePath(
                sharedDB.extensionJetsamMetricsFilePath(),
                withRotatedFilepath: sharedDB.extensionJetsamMetricsRotatedFilePath(),
                registryFilepath: sharedDB.containerJetsamMetricsRegistryFilePath(),
                readChunkSize: 8000,
                binRanges: binRanges)

        let jetsamLog = try metrics.logForFeedback()
        diagnosticEntries.append(DiagnosticEntry(jetsamLog, andTimestamp: getCurrentTime()))
    } catch {
        diagnosticEntries.append(DiagnosticEntry("failed to get jetsam metrics: \(error)", andTimestamp: getCurrentTime()))
    }

    diagnosticEntries.append(appStateFeedbackEntry)

    var clientPlatform = "ios-vpn"
    if #available(iOS 14.0, *) {
        if ProcessInfo().isiOSAppOnMac {
            clientPlatform = "ios-vpn-on-mac"
        }
    }

    do {
        let jsonBlob =
            try Feedback.generateJSON(
                Int(userFeedback.selectedThumbIndex),
                buildInfo: PsiphonTunnel.getBuildInfo(),
                comments: userFeedback.comments,
                email: userFeedback.email,
                sendDiagnosticInfo: userFeedback.uploadDiagnostics,
                feedbackId: userFeedback.feedbackId,
                psiphonConfig: psiphonConfig,
                clientPlatform: clientPlatform,
                connectionType: nil,  // TODO! find a nice way to
                isJailbroken: JailbreakCheck.isDeviceJailbroken(),
                diagnosticEntries: diagnosticEntries,
                statusEntries: .none)
        return .success(jsonBlob)
    } catch {
        let error = ErrorRepr(repr: "failed to generate feedback JSON: \(error)")
        return .failure(error)
    }
}

