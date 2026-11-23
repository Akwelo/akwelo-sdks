#if canImport(UIKit) && canImport(WebKit)
import AVFoundation
import UIKit
import WebKit

/// Entry point.
///
/// ```swift
/// let result = try await Akwelo.verify(sessionToken: token, from: viewController)
/// ```
@MainActor
public enum Akwelo {
    private static var isOpen = false

    /// Presents the capture page and returns the outcome.
    ///
    /// Throws only for arguments that can never work: a blank token (`invalidSessionToken`) or a
    /// base URL that is not https (`invalidBaseURL`). Everything that can go wrong at run time
    /// comes back as a `VerifyResult` with status `.error` and a code; see the README for the list.
    /// One capture at a time: a call made while another is open returns `already_in_progress` at
    /// once and leaves the open one untouched.
    public static func verify(
        sessionToken: String,
        from presenter: UIViewController,
        options: AkweloOptions = AkweloOptions()
    ) async throws -> VerifyResult {
        guard VerifyURL.validBaseOrigin(options.baseURL) != nil else { throw AkweloError.invalidBaseURL }
        _ = try VerifyURL.build(baseURL: options.baseURL, sessionToken: sessionToken)
        // iOS terminates an app that asks for the camera without this key.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") is String else {
            return .failure("missing_camera_usage_description", "Add NSCameraUsageDescription to the app's Info.plist")
        }
        guard !isOpen else { return .failure("already_in_progress", "A verification is already open") }
        isOpen = true
        defer { isOpen = false }

        var attestation: String?
        if options.useAppAttest {
            // Best-effort: the page never waits on Apple's servers.
            attestation = await firstResult(within: AkweloOptions.attestationTimeout) {
                await AppAttest.token(sessionToken: sessionToken)
            }
        }
        // Screen recording, mirroring or AirPlay while the selfie is taken: evidence for Akwelo.
        var capture = HostSignalState()
        _ = capture.set(UIScreen.main.isCaptured)
        let url = try VerifyURL.build(baseURL: options.baseURL, sessionToken: sessionToken,
                                      attestation: attestation, env: capture.env)
        // `present` does nothing, and says nothing, from a controller that is off screen or already
        // presenting. Without this check the caller would wait forever.
        guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else {
            return .failure("presentation_failed", "The presenting view controller is off screen or already presenting")
        }
        return await withCheckedContinuation { continuation in
            let vc = AkweloVerifyViewController(url: url, origin: options.baseURL, capture: capture) { result in
                continuation.resume(returning: result)
            }
            vc.modalPresentationStyle = .fullScreen
            presenter.present(vc, animated: true)
        }
    }

    /// Completion-handler variant.
    public static func verify(
        sessionToken: String,
        from presenter: UIViewController,
        options: AkweloOptions = AkweloOptions(),
        completion: @escaping (Result<VerifyResult, Error>) -> Void
    ) {
        Task { @MainActor in
            do { completion(.success(try await verify(sessionToken: sessionToken, from: presenter, options: options))) }
            catch { completion(.failure(error)) }
        }
    }
}

/// Full-screen WKWebView hosting the capture page. The host app must declare
/// `NSCameraUsageDescription` in Info.plist. Every way out of this screen ends in exactly one
/// call of `onResult`.
final class AkweloVerifyViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    private let url: URL
    private let origin: URL
    private var onResult: ((VerifyResult) -> Void)?
    /// Decided but not yet delivered: the screen is still closing.
    private var outcome: VerifyResult?
    private var webView: WKWebView!
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var capture: HostSignalState
    private var pageLoaded = false

    init(url: URL, origin: URL, capture: HostSignalState, onResult: @escaping (VerifyResult) -> Void) {
        self.url = url
        self.origin = origin
        self.capture = capture
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(captureChanged),
                                               name: UIScreen.capturedDidChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func captureChanged() {
        if capture.set(UIScreen.main.isCaptured) { sendCapture() }
    }

    /// Hands the screen capture state to the page: after every load and on every change.
    private func sendCapture() {
        guard pageLoaded, outcome == nil, let script = capture.script else { return }
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Weak proxy avoids the WKUserContentController retain cycle.
        config.userContentController.add(WeakHandler(self), name: "akwelo")
        // Expose the same `AkweloBridge.postMessage(json)` API the page uses on Android.
        let shim = "window.AkweloBridge = window.AkweloBridge || { postMessage: function (m) { window.webkit.messageHandlers.akwelo.postMessage(m); } };"
        config.userContentController.addUserScript(
            WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.uiDelegate = self
        webView.navigationDelegate = self

        // Always there, so a page that fails to draw can never trap the person: a full-screen
        // modal has no other way out on iOS.
        let close = UIButton(type: .close)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.startAnimating()

        view.addSubview(webView)
        view.addSubview(close)
        view.addSubview(spinner)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
            close.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            close.widthAnchor.constraint(equalToConstant: 32),
            close.heightAnchor.constraint(equalToConstant: 32),
            webView.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 6),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        webView.load(URLRequest(url: url))
    }

    @objc private func closeTapped() {
        finish(VerifyResult(status: .cancelled))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              VerifyURL.isTrusted(message.frameInfo.securityOrigin, base: origin),
              let result = VerifyResult.parse(message.body) else { return }
        finish(result)
    }

    // iOS 15+: grant camera only to the Akwelo origin, without a second WebKit prompt.
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let trusted = VerifyURL.isTrusted(origin, base: self.origin)
        guard trusted, type == .camera else { return decisionHandler(.deny) }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { decisionHandler(granted ? .grant : .deny) }
        }
    }

    // Keep the top-level document on the Akwelo origin so no other site can reach the bridge.
    // A link the person tapped (privacy notice, help) opens in their browser instead.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        guard mainFrame else { return decisionHandler(.allow) }
        if VerifyURL.isTrusted(action.request.url, base: origin) { return decisionHandler(.allow) }
        if action.navigationType == .linkActivated { openOutside(action.request.url) }
        decisionHandler(.cancel)
    }

    // The capture page itself answered with an HTTP error: an error result, not the server's error page.
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame,
           let http = response.response as? HTTPURLResponse,
           http.statusCode >= 400,
           VerifyURL.isTrusted(http.url, base: origin) {
            decisionHandler(.cancel)
            finish(.failure("page_load_failed", "The capture page answered HTTP \(http.statusCode)"))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
        guard VerifyURL.isTrusted(webView.url, base: origin) else { return }
        pageLoaded = true
        sendCapture()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    // The page's process died (low memory is the usual cause); the web view is blank from here on.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure("webview_crashed", "The capture page stopped unexpectedly"))
    }

    // window.open / target=_blank: never spawn an untracked web view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if VerifyURL.isTrusted(action.request.url, base: origin) { webView.load(action.request) }
        return nil
    }

    private func loadFailed(_ error: Error) {
        let e = error as NSError
        let failing = (e.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (e.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap { URL(string: $0) }
        if let result = VerifyURL.resultForLoadError(domain: e.domain, code: e.code, failingURL: failing, base: origin) {
            finish(result)
        }
    }

    private func openOutside(_ url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
        UIApplication.shared.open(url)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Dismissed by the host without a result. When `finish` closed the screen, the dismiss
        // completion delivers instead, so the caller can present its next screen straight away.
        if outcome == nil, isBeingDismissed || presentingViewController == nil { deliver() }
    }

    /// Decides the outcome, closes the screen, then tells the caller. The first call wins.
    private func finish(_ result: VerifyResult) {
        guard onResult != nil, outcome == nil else { return }
        outcome = result
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "akwelo")
        webView?.stopLoading()
        if let coordinator = transitionCoordinator {
            // Still animating in. UIKit drops a dismiss made now, and the caller would wait forever.
            _ = coordinator.animate(alongsideTransition: nil) { [self] _ in dismissThenDeliver() }
        } else {
            dismissThenDeliver()
        }
    }

    private func dismissThenDeliver() {
        guard presentingViewController != nil else { return deliver() }
        dismiss(animated: true) { [self] in deliver() }
        // Safety net: should UIKit never run that completion, the caller still gets its answer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in deliver() }
    }

    /// Tells the caller, once, however many paths reach it.
    private func deliver() {
        guard let callback = onResult else { return }
        onResult = nil
        callback(outcome ?? VerifyResult(status: .cancelled))
    }
}

extension VerifyURL {
    @MainActor
    static func isTrusted(_ o: WKSecurityOrigin, base: URL) -> Bool {
        let port = o.port == 0 ? nil : o.port
        return origin(scheme: o.protocol, host: o.host, port: port) == origin(of: base)
    }
}

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
#endif
