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
    public static func verify(
        sessionToken: String,
        from presenter: UIViewController,
        options: AkweloOptions = AkweloOptions()
    ) async throws -> VerifyResult {
        var attestation: String?
        if options.useAppAttest { attestation = await AppAttest.token(sessionToken: sessionToken) }
        let url = try VerifyURL.build(baseURL: options.baseURL, sessionToken: sessionToken, attestation: attestation)
        return await withCheckedContinuation { continuation in
            let vc = AkweloVerifyViewController(url: url, origin: options.baseURL) { result in
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
/// `NSCameraUsageDescription` in Info.plist.
final class AkweloVerifyViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    private let url: URL
    private let origin: URL
    private var onResult: ((VerifyResult) -> Void)?
    private var webView: WKWebView!

    init(url: URL, origin: URL, onResult: @escaping (VerifyResult) -> Void) {
        self.url = url
        self.origin = origin
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
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
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        view.addSubview(webView)
        webView.load(URLRequest(url: url))
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
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        guard mainFrame else { return decisionHandler(.allow) }
        decisionHandler(VerifyURL.isTrusted(action.request.url, base: origin) ? .allow : .cancel)
    }

    // window.open / target=_blank: never spawn an untracked web view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Swiped down / dismissed by the host without a result.
        if isBeingDismissed || presentingViewController == nil { finish(VerifyResult(status: .cancelled), dismiss: false) }
    }

    private func finish(_ result: VerifyResult, dismiss: Bool = true) {
        guard let cb = onResult else { return }
        onResult = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "akwelo")
        if dismiss { self.dismiss(animated: true) { cb(result) } } else { cb(result) }
    }
}

extension VerifyURL {
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
