import Foundation

/// Capture outcome reported by the hosted page. The verification decision is delivered to your backend.
public enum VerifyStatus: String, Sendable, Equatable {
    case submitted, cancelled, error
}

public struct VerifyResult: Sendable, Equatable {
    public static let messageType = "akwelo.verify.result"

    public let status: VerifyStatus
    public let sessionId: String?
    public let error: String?

    public init(status: VerifyStatus, sessionId: String? = nil, error: String? = nil) {
        self.status = status
        self.sessionId = sessionId
        self.error = error
    }

    /// Parses a bridge message (a JSON string or an already-decoded dictionary).
    /// Returns nil for anything that is not an Akwelo result.
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
        let sid = (d["sessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return VerifyResult(status: status, sessionId: sid, error: d["error"] as? String)
    }
}
