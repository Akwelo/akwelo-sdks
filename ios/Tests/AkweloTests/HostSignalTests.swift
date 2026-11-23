import XCTest
@testable import Akwelo

final class HostSignalTests: XCTestCase {
    /// Decoded the way the hosted page does (readHostEnv in apps/flow): base64url, padding optional.
    private func decode(_ v: String) -> String? {
        var b64 = v.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) }
    }

    func testPayloadJSON() {
        XCTAssertEqual(HostSignal.json(active: true, seen: false), #"{"screen_capture":"active","source":"ios"}"#)
        XCTAssertEqual(HostSignal.json(active: false, seen: true),
                       #"{"screen_capture":"inactive","source":"ios","screen_capture_seen":true}"#)
    }

    func testEnvFragmentIsBase64URLJSON() throws {
        let env = HostSignal.env(active: true, seen: true)
        XCTAssertNil(env.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertEqual(decode(env), #"{"screen_capture":"active","source":"ios","screen_capture_seen":true}"#)
        let url = try VerifyURL.build(baseURL: AkweloOptions.defaultBaseURL, sessionToken: "abc", env: env)
        XCTAssertEqual(url.absoluteString, "https://flow.akwelo.com/verify/selfie#token=abc&env=\(env)")
    }

    func testScriptNeverThrowsInThePage() {
        XCTAssertEqual(HostSignal.script(active: false, seen: false),
                       #"try{window.AkweloHost&&window.AkweloHost.signal({"screen_capture":"inactive","source":"ios"})}catch(e){}"#)
    }

    func testStateReportsChangesAndRemembersACapture() {
        var s = HostSignalState()
        XCTAssertNil(s.script)
        XCTAssertTrue(s.set(false))
        XCTAssertFalse(s.set(false))
        XCTAssertFalse(s.seen)
        XCTAssertTrue(s.set(true))
        XCTAssertFalse(s.set(true))
        XCTAssertTrue(s.set(false))
        XCTAssertTrue(s.seen) // kept after the capture stopped
        XCTAssertEqual(s.script, HostSignal.script(active: false, seen: true))
        XCTAssertFalse(s.markSeen())
    }
}
