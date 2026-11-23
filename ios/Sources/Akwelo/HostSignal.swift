import Foundation

/// The capture environment report the hosted page receives through `window.AkweloHost.signal(...)`
/// (after every load and on every change) and, for the first value, as `env=` in the fragment:
/// `{"screen_capture":"active|inactive","source":"ios"[,"screen_capture_seen":true]}`.
/// Evidence for Akwelo's server, never a verdict.
enum HostSignal {
    static let source = "ios"

    /// Fixed keys and values, so the JSON is written by hand in a stable order.
    static func json(active: Bool, seen: Bool) -> String {
        var s = #"{"screen_capture":""# + (active ? "active" : "inactive") + #"","source":""# + source + #"""#
        if seen { s += #","screen_capture_seen":true"# }
        return s + "}"
    }

    /// base64url JSON without padding, for `env=`.
    static func env(active: Bool, seen: Bool) -> String {
        Data(json(active: active, seen: seen).utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// JavaScript that hands the report to the page; it never throws, whatever state the page is in.
    static func script(active: Bool, seen: Bool) -> String {
        "try{window.AkweloHost&&window.AkweloHost.signal(" + json(active: active, seen: seen) + ")}catch(e){}"
    }
}

/// Screen capture as last observed, and whether any was seen since the capture screen opened.
struct HostSignalState {
    private(set) var active: Bool?
    private(set) var seen = false

    /// Records an observation; answers whether what the page should hear changed.
    mutating func set(_ value: Bool) -> Bool {
        let changed = active != value || (value && !seen)
        active = value
        if value { seen = true }
        return changed
    }

    /// A capture happened without changing the current state; answers whether that is news.
    mutating func markSeen() -> Bool {
        if seen { return false }
        seen = true
        return true
    }

    var script: String? { active.map { HostSignal.script(active: $0, seen: seen) } }
    var env: String? { active.map { HostSignal.env(active: $0, seen: seen) } }
}
