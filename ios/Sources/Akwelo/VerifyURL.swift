import Foundation

public enum AkweloError: Error, Equatable {
    case invalidSessionToken
    case invalidBaseURL
}

public struct AkweloOptions: Sendable {
    public static let defaultBaseURL = URL(string: "https://flow.akwelo.com")!

    /// Hosted capture origin. Override for staging or self-hosted deployments.
    public var baseURL: URL
    /// Send an App Attest assertion as `attest=` when the device supports it.
    /// TODO(akwelo): requires an Apple Developer team with the App Attest entitlement and
    /// server-side key registration; off by default until that exists.
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

    /// Builds `{baseUrl}/verify/selfie#token=...[&attest=...]`. Secrets stay in the fragment.
    static func build(baseURL: URL, sessionToken: String, attestation: String? = nil) throws -> URL {
        guard !sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AkweloError.invalidSessionToken
        }
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var s = base + "/verify/selfie#token=" + encode(sessionToken)
        if let a = attestation, !a.isEmpty { s += "&attest=" + encode(a) }
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

    private static func encode(_ v: String) -> String {
        v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
    }
}
