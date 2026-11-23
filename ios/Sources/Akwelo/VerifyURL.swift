import Foundation

public enum AkweloError: Error, Equatable {
    case invalidSessionToken
    case invalidBaseURL
}

public struct AkweloOptions: Sendable {
    public static let defaultBaseURL = URL(string: "https://flow.akwelo.com")!

    /// How long capture waits for an attestation before starting without one.
    public static let attestationTimeout: TimeInterval = 5

    /// Hosted capture origin. Override for staging or self-hosted deployments. Must be https
    /// (plain http is accepted only for a development server on this machine).
    public var baseURL: URL
    /// Send an App Attest attestation as `attest=` when the device supports it. Capture never
    /// waits on it: none within `attestationTimeout` means the page loads without one.
    /// Requires an Apple Developer team with the App Attest entitlement. Off by default.
    public var useAppAttest: Bool

    public init(baseURL: URL = AkweloOptions.defaultBaseURL, useAppAttest: Bool = false) {
        self.baseURL = baseURL
        self.useAppAttest = useAppAttest
    }
}

enum VerifyURL {
    private static let allowed: CharacterSet = {
        var c = CharacterSet.alphanumerics
        c.insert(charactersIn: "-._~")
        return c
    }()

    /// Builds `{baseUrl}/verify/selfie#token=...[&attest=...][&env=...]`. Secrets stay in the
    /// fragment. `env` is the first screen capture report (`HostSignal.env`).
    static func build(baseURL: URL, sessionToken: String, attestation: String? = nil, env: String? = nil) throws -> URL {
        guard !sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AkweloError.invalidSessionToken
        }
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var s = base + "/verify/selfie#token=" + encode(sessionToken)
        if let a = attestation, !a.isEmpty { s += "&attest=" + encode(a) }
        if let e = env, !e.isEmpty { s += "&env=" + encode(e) }
        guard let url = URL(string: s) else { throw AkweloError.invalidBaseURL }
        return url
    }

    /// `scheme://host[:port]`, lower-cased, default ports dropped. Nil for URLs without a host or with userinfo.
    static func origin(of url: URL?) -> String? {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.user == nil, c.password == nil else { return nil }
        return origin(scheme: c.scheme, host: c.host, port: c.port)
    }

    static func origin(scheme: String?, host: String?, port: Int?) -> String? {
        guard let s = scheme?.lowercased(), let h = host?.lowercased(), !h.isEmpty else { return nil }
        if let p = port, !((s == "https" && p == 443) || (s == "http" && p == 80)) { return "\(s)://\(h):\(p)" }
        return "\(s)://\(h)"
    }

    static func isTrusted(_ url: URL?, base: URL) -> Bool {
        guard let o = origin(of: url) else { return false }
        return o == origin(of: base)
    }

    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// The origin of a usable base URL, or nil. The page handles a camera and a session token, so
    /// it must be https; plain http is accepted only for a development server on this machine.
    static func validBaseOrigin(_ url: URL?) -> String? {
        guard let url, let o = origin(of: url) else { return nil }
        if o.hasPrefix("https://") { return o }
        guard o.hasPrefix("http://"), let host = url.host?.lowercased(), localHosts.contains(host) else { return nil }
        return o
    }

    /// What a failed main-frame load means for the capture: an error result, or nil to ignore it
    /// (a link the person tapped that did not open, or a navigation the SDK itself stopped).
    static func resultForLoadError(domain: String, code: Int, failingURL: URL?, base: URL) -> VerifyResult? {
        // A navigation the app cancelled: NSURLErrorCancelled, or WebKit's "frame load interrupted".
        if domain == NSURLErrorDomain, code == NSURLErrorCancelled { return nil }
        if domain == "WebKitErrorDomain", code == 102 { return nil }
        if let failingURL, !isTrusted(failingURL, base: base) { return nil }
        return .failure("page_load_failed", "The capture page did not load (\(domain) \(code))")
    }

    private static func encode(_ v: String) -> String {
        v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
    }
}
