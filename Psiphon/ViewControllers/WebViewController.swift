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
import WebKit
import PsiApi
import Utilities
import ReactiveSwift
import SafariServices

fileprivate enum WebViewFailure: HashableError {
    case didFail(SystemError<Int>)
    case didFailProvisionalNavigation(SystemError<Int>)
    case httpError(ErrorMessage)
}

fileprivate typealias WebViewLoadingState = Pending<Result<Utilities.Unit,
                                                           ErrorEvent<WebViewFailure>>>


/// A WKWebView view controller, with no navigation back/forward buttons.
/// Links with the `target="_blank"` attribute will opened in a `SFSafariViewController`,
/// presented on top of this view controller.
///
/// Note regarding PsiCash Accounts website (or any other websit:
/// Formal contract between PsiCash Accounts website and platforms that use webviews:
/// - All links that lead to a outside websites (even those owened by Psiphon)
///   should have the `target="_blank"` attribute or use `window.open` call.
/// - Return value of `window.open` will be nil.
/// - Webviews are not required to have navigation back/forward buttons. The intention is for the
///   experience to feel as native as possible.
///   Users should be able to navigate to anywhere within the PsiCash Accounts website from any page.
///
final class WebViewController: ReactiveViewController {
    
    private struct ObservedState: Equatable {
        let webViewLoading: WebViewLoadingState
        let tunnelStatus: TunnelProviderVPNStatus
        let lifeCycle: ViewControllerLifeCycle
    }
    
    private let (lifetime, token) = Lifetime.make()
    private let tunnelProviderRefSignal: SignalProducer<TunnelConnection?, Never>
    private let feedbackLogger: FeedbackLogger
    
    private let baseURL: URL
    
    private let webView: WKWebView
    private var containerView: ViewBuilderContainerView<
        EitherView<PlaceholderView<WKWebView>, BlockerView>>!
    
    /// State of loading content for the main frame.
    @State private var mainFrameLoadState: WebViewLoadingState = .pending
    
    init(
        baseURL: URL,
        feedbackLogger: FeedbackLogger,
        tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
        tunnelProviderRefSignal: SignalProducer<TunnelConnection?, Never>,
        onDismissed: @escaping () -> Void
    ) {
        
        self.baseURL = baseURL
        self.tunnelProviderRefSignal = tunnelProviderRefSignal
        self.feedbackLogger = feedbackLogger
        
        self.webView = WKWebView(frame: .zero)
        
        super.init(onDismissed: onDismissed)
        
        mutate(self.webView) {
            $0.uiDelegate = self
            $0.navigationDelegate = self
        }
        
        self.containerView = ViewBuilderContainerView(
            EitherView(
                PlaceholderView(),
                BlockerView()
            )
        )
        
        // Stops the webview from loading of all resources
        // if the tunnel status is not connected.
        // No-op if nothing is loading.
        self.lifetime += tunnelStatusSignal
            .skipRepeats()
            .startWithValues { [unowned self] tunnelProviderVPNStatus in
                
                guard case .connected = tunnelProviderVPNStatus.tunneled else {
                    self.webView.stopLoading()
                    return
                }
                
            }
        
        self.lifetime += SignalProducer.combineLatest(
            self.$mainFrameLoadState.signalProducer,
            tunnelStatusSignal,
            self.$lifeCycle.signalProducer
        ).map(ObservedState.init)
        .skipRepeats()
        .filter { observed in
            observed.lifeCycle.viewDidLoadOrAppeared
        }
        .startWithValues { [unowned self] observed in
            
            if Debugging.mainThreadChecks {
                guard Thread.isMainThread else {
                    fatalError()
                }
            }
            
            // Even though the reactive signal has a filter on
            // `!observed.lifeCycle.viewWillOrDidDisappear`, due to async nature
            // of the signal it is ambiguous if this closure is called when
            // `self.lifeCycle.viewWillOrDidDisappear` is true.
            // Due to this race-condition, the source-of-truth (`self.lifeCycle`),
            // is checked for whether view will or did disappear.
            guard !self.lifeCycle.viewWillOrDidDisappear else {
                return
            }
            
            switch observed.tunnelStatus.tunneled {
            
            case .notConnected:
                
                self.containerView.bind(
                    .right(
                        BlockerView.DisplayOption(
                            animateSpinner: false,
                            viewOptions: .label(text: UserStrings.Psiphon_is_not_connected()))))
                
            case .connecting:
                
                self.containerView.bind(
                    .right(
                        BlockerView.DisplayOption(
                            animateSpinner: true,
                            viewOptions: .label(text: UserStrings.Connecting_to_psiphon()))))
                
            case .disconnecting:
                
                self.containerView.bind(
                    .right(
                        BlockerView.DisplayOption(
                            animateSpinner: false,
                            viewOptions: .label(text: UserStrings.Psiphon_is_not_connected()))))
                
            case .connected:
                
                switch observed.webViewLoading {
                case .pending:

                    // Loading
                    feedbackLogger.immediate(.info, "loading")
                    
                    self.containerView.bind(
                        .right(
                            BlockerView.DisplayOption(
                                animateSpinner: true,
                                viewOptions: .label(text: UserStrings.Loading()))))
                    
                case .completed(.success(_)):
                    
                    // Load is complete
                    feedbackLogger.immediate(.info, "load completed")
                    
                    self.containerView.bind(.left(self.webView))
                    
                case .completed(.failure(let errorEvent)):
                    
                    // Load failed
                    feedbackLogger.immediate(.info, "load failed: \(errorEvent)")
                    
                    let retryButton = BlockerView.DisplayOption.ButtonOption(
                        title: UserStrings.Tap_to_retry(),
                        handler: BlockerView.Handler { [unowned self] () -> Void in
                            // Retries to load the baseURL again.
                            self.load(url: baseURL)
                        }
                    )
                    
                    self.containerView.bind(
                        .right(
                            .init(animateSpinner: false,
                                  viewOptions: .labelAndButton(
                                    labelText: UserStrings.Loading_failed(),
                                    buttonOptions: [ retryButton ]
                                  ))))
                    
                }
                
            }
            
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let navigationController = navigationController {
            
            let closeNavBtn = UIBarButtonItem(title: UserStrings.Close_button_title(),
                                              style: .plain,
                                              target: self,
                                              action: #selector(onNavCloseButtonClicked))
            
            self.navigationItem.leftBarButtonItem = closeNavBtn
            
            // Fixes navigation bar appearance when scrolling
            navigationController.navigationBar.applyStandardAppearanceToScrollEdge()
            
        }
        
        self.view.addSubview(self.containerView.view)
        
        // Setup Auto Layout
        self.containerView.view.activateConstraints {
            $0.matchParentConstraints()
        }
        
        // Starts loading of baseURL
        self.load(url: baseURL)
        
    }
    
    // Only use this function for loading or relading a url.
    // Do not directly call `self.webView`.
    private func load(url: URL) {
        self.mainFrameLoadState = .pending
        self.webView.load(URLRequest(url: url))
    }
    
    // Navigation bar close button click handler.
    @objc private func onNavCloseButtonClicked() {
        self.dismiss(animated: true, completion: nil)
    }
    
    private func presentInNewWindow(url: URL) {
        let safari = SFSafariViewController(url: url)
        self.present(safari, animated: true, completion: nil)
    }
    
}

extension WebViewController: WKUIDelegate {
    
    func webViewDidClose(_ webView: WKWebView) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        
        // Handles JS window.open call by opening the link in a new SFSafariViewController
        // presented on top of this view controller.
        
        guard let url = navigationAction.request.url else {
            return nil
        }
        
        presentInNewWindow(url: url)
        
        return nil
        
    }
    
}

extension WebViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Tells the delegate that an error occurred during navigation.
        
        self.mainFrameLoadState = .completed(
            .failure(
                ErrorEvent(
                    .didFail(SystemError<Int>.make(error as NSError)),
                    date: Date()
                )
            )
        )
        
    }
    
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // This callback is *not* always called after
        // webView:decidePolicyForNavigationResponse:decisionHandler:.
        
        // If an error value has been set by
        // webView:decidePolicyForNavigationResponse:decisionHandler:,
        // then returns immediately.
        if case .completed(.failure(_)) = self.mainFrameLoadState {
            return
        }
        
        // Tells the delegate that an error occurred during the early navigation process.
        let systemError = SystemError<Int>.make(error as NSError)
        
        self.mainFrameLoadState = .completed(
            .failure(
                ErrorEvent(
                    .didFailProvisionalNavigation(systemError),
                    date: Date()
                )
            )
        )
        
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Tells the delegate that navigation is complete.
        self.mainFrameLoadState = .completed(.success(.unit))
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Asks the delegate for permission to navigate to new content
        // after the response to the navigation request is known.
        
        guard navigationResponse.isForMainFrame else {
            decisionHandler(.allow)
            return
        }
        
        let httpStatus = (navigationResponse.response as! HTTPURLResponse).statusCode
        
        // If recieved client or server http status error code,
        // cancels navigation, and updates `self.webViewLoading`.
        // The webview is expected to be blocked with an error message at this point.
        switch httpStatus {
        
        case 400..<500, // Client error
             500..<600: // Server error
                        
            self.mainFrameLoadState = .completed(
                .failure(
                    ErrorEvent(
                        .httpError(ErrorMessage("received HTTP status \(httpStatus)")),
                        date: Date()
                    )
                )
            )
            
            decisionHandler(.cancel)
            
        default:
            self.mainFrameLoadState = .pending
            decisionHandler(.allow)
        }
        
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        
        // If delegate object implements the
        // webView(_:decidePolicyFor:preferences:decisionHandler:) method,
        // the web view doesn’t call this method.
        
        // If the target of the navigation is a new window,
        // navigationAction.targetFrame property is nil.
        guard let targetFrame = navigationAction.targetFrame else {
            // Handles links with `target="_blank"` attribute by opening
            // the URL in a new SFSafariViewController presented
            // on top of this view controller.
            presentInNewWindow(url: navigationAction.request.url!)
            decisionHandler(.cancel)
            return
        }
        
        tunnelProviderRefSignal
            .take(first: 1)
            .startWithValues { [unowned self] tunnelConnection in
                
                switch tunnelConnection?.tunneled {
                case .connected:
                    
                    // Navigation action is allowed only if the tunnel is connected.
                    decisionHandler(.allow)
                    
                default:
                    decisionHandler(.cancel)
                }
                
            }
        
    }
    
}
