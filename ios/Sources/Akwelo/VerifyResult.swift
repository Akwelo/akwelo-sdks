import Foundation

/// Capture outcome reported by the hosted page. The verification decision is delivered to your backend.
public enum VerifyStatus: String, Sendable, Equatable {
    case submitted, cancelled, error
}

public struct VerifyResult: Sendable, Equatable {
    public static let messageType = "akwelo.verify.result"

    public let status: VerifyStatus
    public let sessionId: String?
    /// Stable error code when `status` is `.error`, for example `camera_unavailable`. See README.
    public let error: String?
    /// Text for a person, in the page's language when the page reported the error.
    public let errorMessage: String?

    public init(status: VerifyStatus, sessionId: String? = nil, error: String? = nil, errorMessage: String? = nil) {
        self.status = status
        self.sessionId = sessionId
        self.error = error
        self.errorMessage = errorMessage
    }

    /// An SDK-side failure, in the same shape as one the page reports.
    static func failure(_ code: String, _ message: String) -> VerifyResult {
        VerifyResult(status: .error, error: code, errorMessage: message)
    }

    /// Parses a bridge message (a JSON string or an already-decoded dictionary).
    /// Returns nil for anything that is not an Akwelo result.
    /// The page sends `error` as `{code, message}`; a bare string is read as the code.
    public static func parse(_ body: Any?) -> VerifyResult? {
        var dict = body as? [String: Any]
        if dict == nil, let s = body as? String, let data = s.data(using: .utf8) {
            dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let d = dict,
              d["type"] as? String == messageType,
              let raw = d["status"] as? String,
              let status = VerifyStatus(rawValue: raw)
        else { return nil }
        var code: String?
        var message: String?
        if let s = d["error"] as? String {
            code = text(s)
        } else if let e = d["error"] as? [String: Any] {
            code = text(e["code"] as? String)
            message = text(e["message"] as? String)
        }
        // An error always carries a code, so callers can switch on it.
        if status == .error, code == nil { code = "unknown_error" }
        return VerifyResult(status: status, sessionId: text(d["sessionId"] as? String), error: code, errorMessage: message)
    }

    private static func text(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
